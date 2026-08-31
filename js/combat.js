/* ============================================================
   COMBAT SIMULATION
   Fixed-timestep hex battle sim. Runs identically headless (for
   AI-vs-AI matches) and rendered (for the player's own fight).
   ============================================================ */
'use strict';

const TICK = 1 / 30;
const COMBAT_TIME_LIMIT = 42;
const BASE_CRIT = 0.25;
const BASE_CRIT_DMG = 1.4;
const MOVE_TIME = 0.34;      // seconds to cross one hex
const CAST_TIME = 0.22;
const AS_CAP = 5.0;

function makeUnit(sim, entry, team) {
  const champ = CHAMP_BY_ID[entry.champId];
  const st = statsFor(champ, entry.star);
  const u = {
    uid: U.uid(), champ, champId: champ.id, star: entry.star, team,
    col: entry.col, row: entry.row, homeCol: entry.col, homeRow: entry.row,
    maxHp: st.maxHp, hp: st.maxHp, shield: 0, shields: [],
    mana: st.manaStart, maxMana: st.maxMana, manaRegen: 0,
    ad: st.ad, ap: 100, armor: st.armor, mr: st.mr, as: st.as, range: st.range,
    crit: BASE_CRIT, critDmg: BASE_CRIT_DMG, omnivamp: 0, dr: 0, damageAmp: 0,
    dodge: 0, executeAmp: 0, itemRegen: 0,
    items: (entry.items || []).slice(),
    alive: true, target: null, attackTimer: 0, casting: 0, stunT: 0,
    x: 0, y: 0, moving: null,
    rend: 0, rendT: 0, shredMr: 0, shredMrT: 0, burns: [], buffs: [], flats: [],
    regen: null, regenQueue: [], revive: null, tempOmni: 0, tempOmniT: 0,
    dmgDealt: 0, healDone: 0,
    hooks: { onAttack: [], onDamaged: [], onCast: [], onKill: [], onDeath: [] }
  };
  const p = U.hexPos(u.col, u.row);
  u.x = p.x; u.y = p.y;
  return u;
}

class Sim {
  constructor(boardA, boardB, opts) {
    opts = opts || {};
    this.render = !!opts.render;
    this.t = 0;
    this.done = false;
    this.winner = -1;
    this.units = [];
    this.teams = [[], []];
    this.events = [];
    this.timers = [];
    this.fxq = [];
    this.occ = new Map();

    for (const e of boardA) {
      const u = makeUnit(this, e, 0);
      this.units.push(u); this.teams[0].push(u);
    }
    for (const e of boardB) {
      // mirror the opponent board onto the top half
      const u = makeUnit(this, { champId: e.champId, star: e.star, items: e.items, col: BOARD.COLS - 1 - e.col, row: BOARD.ROWS - 1 - e.row }, 1);
      this.units.push(u); this.teams[1].push(u);
    }
    for (const u of this.units) this.occ.set(U.cellKey(u.col, u.row), u);

    // items first, then traits (so % bonuses apply to item stats too)
    for (const u of this.units) {
      for (const id of u.items) {
        const it = ITEMS[id];
        if (it && it.apply) it.apply(u, this);
      }
    }
    this.activeTraits = [[], []];
    for (let t = 0; t < 2; t++) this.applyTraits(t);

    for (const u of this.units) { u.as = Math.min(u.as, AS_CAP); u.hp = u.maxHp; }
  }

  /* ---------------- trait setup ---------------- */
  applyTraits(teamId) {
    const team = this.teams[teamId];
    const counts = {};
    const seen = {};
    for (const u of team) {
      for (const tr of u.champ.traits) {
        if (!seen[tr]) seen[tr] = new Set();
        seen[tr].add(u.champId);
      }
    }
    for (const tr in seen) counts[tr] = seen[tr].size;
    for (const trId in counts) {
      const trait = TRAITS[trId];
      const ti = traitTierIdx(trait, counts[trId]);
      if (ti < 0) continue;
      const holders = team.filter(u => u.champ.traits.indexOf(trId) >= 0);
      this.activeTraits[teamId].push({ id: trId, count: counts[trId], ti });
      trait.apply({ sim: this, team, holders, ti, count: counts[trId], teamId });
    }
  }

  /* ---------------- queries ---------------- */
  ap(u) { return u.ap / 100; }
  dist(a, b) { return U.hexDist(a.col, a.row, b.col, b.row); }

  livingAllies(teamId) { return this.teams[teamId].filter(u => u.alive); }
  livingEnemies(teamId) { return this.teams[1 - teamId].filter(u => u.alive); }

  enemiesNear(ref, r, teamOf) {
    const tid = teamOf === undefined ? ref.team : teamOf;
    return this.units.filter(u => u.alive && u.team !== tid && u !== ref &&
      U.hexDist(u.col, u.row, ref.col, ref.row) <= r);
  }
  alliesNear(ref, r) {
    return this.teams[ref.team].filter(u => u.alive && U.hexDist(u.col, u.row, ref.col, ref.row) <= r);
  }
  nearestEnemies(u, n) {
    return this.livingEnemies(u.team).sort((a, b) => this.dist(u, a) - this.dist(u, b)).slice(0, n);
  }
  lowestEnemy(teamId) {
    const f = this.livingEnemies(teamId);
    if (!f.length) return null;
    return f.reduce((a, b) => (a.hp <= b.hp ? a : b));
  }
  lowestAlly(teamId) {
    const f = this.livingAllies(teamId);
    if (!f.length) return null;
    return f.reduce((a, b) => (a.hp / a.maxHp <= b.hp / b.maxHp ? a : b));
  }
  farthestEnemy(u) {
    const f = this.livingEnemies(u.team);
    if (!f.length) return null;
    return f.reduce((a, b) => (this.dist(u, a) >= this.dist(u, b) ? a : b));
  }
  pickTarget(u) {
    if (u.target && u.target.alive) return u.target;
    return this.acquire(u);
  }
  bestCluster(teamId, radius) {
    const foes = this.livingEnemies(teamId);
    if (!foes.length) return null;
    let best = null;
    for (let r = 0; r < BOARD.ROWS; r++) {
      for (let c = 0; c < BOARD.COLS; c++) {
        const list = foes.filter(f => U.hexDist(f.col, f.row, c, r) <= radius);
        if (!best || list.length > best.list.length) {
          const p = U.hexPos(c, r);
          best = { col: c, row: r, x: p.x, y: p.y, list };
        }
      }
    }
    return best && best.list.length ? best : null;
  }
  lineTargets(src, tgt, len) {
    const dx = tgt.x - src.x, dy = tgt.y - src.y;
    const L = Math.hypot(dx, dy) || 1;
    const ux = dx / L, uy = dy / L;
    const maxD = len * BOARD.HEX_W;
    return this.livingEnemies(src.team).filter(e => {
      const ex = e.x - src.x, ey = e.y - src.y;
      const proj = ex * ux + ey * uy;
      if (proj < 0 || proj > maxD) return false;
      const perp = Math.abs(ex * uy - ey * ux);
      return perp < BOARD.HEX_W * 0.62;
    });
  }

  /* ---------------- board occupancy ---------------- */
  cellFree(c, r) {
    return c >= 0 && c < BOARD.COLS && r >= 0 && r < BOARD.ROWS && !this.occ.has(U.cellKey(c, r));
  }
  place(u, c, r) {
    this.occ.delete(U.cellKey(u.col, u.row));
    u.col = c; u.row = r;
    this.occ.set(U.cellKey(c, r), u);
    const p = U.hexPos(c, r);
    u.x = p.x; u.y = p.y; u.moving = null;
  }
  freeCellNear(col, row, prefer) {
    if (this.cellFree(col, row)) return [col, row];
    let best = null, bestD = 1e9;
    for (let r = 0; r < BOARD.ROWS; r++) {
      for (let c = 0; c < BOARD.COLS; c++) {
        if (!this.cellFree(c, r)) continue;
        const d = U.hexDist(c, r, col, row) * 10 + (prefer ? U.hexDist(c, r, prefer.col, prefer.row) : 0);
        if (d < bestD) { bestD = d; best = [c, r]; }
      }
    }
    return best;
  }
  blinkNear(u, target) {
    const cell = this.adjacentFree(target, u);
    if (cell) { this.place(u, cell[0], cell[1]); this.fx('blink', u, null, '#ffffff'); }
  }
  pullTo(anchor, target) {
    const cell = this.adjacentFree(anchor, target);
    if (cell) { this.place(target, cell[0], cell[1]); target.moving = null; }
  }
  adjacentFree(around, toward) {
    const opts = U.hexNeighbors(around.col, around.row).filter(n => this.cellFree(n[0], n[1]));
    if (!opts.length) return null;
    if (!toward) return opts[0];
    opts.sort((a, b) => U.hexDist(a[0], a[1], toward.col, toward.row) - U.hexDist(b[0], b[1], toward.col, toward.row));
    return opts[0];
  }

  /* ---------------- scheduling ---------------- */
  delay(sec, fn) { this.events.push({ t: this.t + sec, fn }); }
  addTimer(first, interval, fn) { this.timers.push({ next: this.t + first, interval, fn }); }

  /* ---------------- visual effects ---------------- */
  fx(kind, target, source, color) {
    if (!this.render || !target) return;
    this.fxq.push({
      kind,
      x: target.x !== undefined ? target.x : 0, y: target.y !== undefined ? target.y : 0,
      sx: source ? source.x : null, sy: source ? source.y : null,
      color: color || '#fff'
    });
  }
  floatText(u, text, cls) {
    if (!this.render) return;
    this.fxq.push({ kind: 'text', x: u.x, y: u.y, text, cls });
  }

  /* ---------------- buffs / statuses ---------------- */
  addShield(u, amt, dur) {
    if (!u.alive) return;
    u.shields.push({ amt, t: dur });
    u.shield = u.shields.reduce((s, x) => s + x.amt, 0);
  }
  addBuff(u, stat, mult, dur) {
    // no clamping here - the cap is applied when attack speed is used,
    // so removing the buff always restores the original value exactly
    u[stat] *= mult;
    u.buffs.push({ stat, mult, t: dur });
  }
  addFlat(u, stat, val, dur) {
    u[stat] += val;
    u.flats.push({ stat, val, t: dur });
  }
  addTempOmni(u, val, dur) { u.tempOmni = val; u.tempOmniT = dur; }
  stun(u, dur) { if (u.alive) { u.stunT = Math.max(u.stunT, dur); this.fx('stun', u, null, '#ffe07a'); } }
  applyShred(u, pct, dur) { u.rend = Math.max(u.rend, pct); u.rendT = Math.max(u.rendT, dur); }
  applyShredMr(u, pct, dur) { u.shredMr = Math.max(u.shredMr, pct); u.shredMrT = Math.max(u.shredMrT, dur); }
  applyBurn(u, pctPerSec, dur, src) {
    u.burns = [{ pct: pctPerSec, t: dur, src, tick: 1 }];
    u.healCut = 0.33; u.healCutT = dur;
  }

  /* ---------------- damage & healing ---------------- */
  damage(src, tgt, amount, type, opts) {
    if (!tgt || !tgt.alive || amount <= 0) return 0;
    opts = opts || {};
    let amt = amount;

    if (src) {
      amt *= (1 + (src.damageAmp || 0));
      if (src.executeAmp && tgt.hp / tgt.maxHp < 0.5) amt *= (1 + src.executeAmp);
    }
    let crit = false;
    if (src && (opts.isAttack || opts.canCrit) && Math.random() < src.crit) {
      crit = true; amt *= src.critDmg;
    }

    const pre = amt;
    if (type === 'physical') {
      let res = tgt.armor * (1 - tgt.rend);
      res *= (1 - (opts.pen || 0));
      amt *= 100 / (100 + Math.max(0, res));
    } else if (type === 'magic') {
      let res = tgt.mr * (1 - tgt.shredMr);
      res *= (1 - (opts.pen || 0));
      amt *= 100 / (100 + Math.max(0, res));
    }
    amt *= (1 - (tgt.dr || 0));
    amt = Math.max(0, amt);

    // shields soak first
    let remaining = amt;
    while (remaining > 0 && tgt.shields.length) {
      const s = tgt.shields[0];
      const used = Math.min(s.amt, remaining);
      s.amt -= used; remaining -= used;
      if (s.amt <= 0.001) tgt.shields.shift();
    }
    tgt.shield = tgt.shields.reduce((s, x) => s + x.amt, 0);
    tgt.hp -= remaining;

    if (src) { src.dmgDealt += amt; }
    this.floatText(tgt, Math.round(amt) + (crit ? '!' : ''),
      type === 'magic' ? 'dmg magic' : type === 'true' ? 'dmg true' : (crit ? 'dmg crit' : 'dmg'));

    // target builds mana from being hit
    if (tgt.maxMana > 0 && !tgt.casting) {
      tgt.mana = Math.min(tgt.maxMana, tgt.mana + Math.min(42.5, pre * 0.01 + amt * 0.07));
    }
    for (const h of tgt.hooks.onDamaged) h(tgt, amt, src);

    // omnivamp
    if (src && src.alive) {
      const ov = (src.omnivamp || 0) + (src.tempOmni || 0);
      if (ov > 0) this.heal(src, src, amt * ov);
    }

    if (tgt.hp <= 0) {
      if (src) for (const h of src.hooks.onKill) h(src, tgt);
      this.kill(tgt, src);
    }
    return amt;
  }

  execute(src, tgt) {
    if (!tgt.alive) return;
    tgt.hp = 0; tgt.shields = []; tgt.shield = 0;
    this.floatText(tgt, 'DEVOURED', 'dmg exec');
    if (src) for (const h of src.hooks.onKill) h(src, tgt);
    this.kill(tgt, src);
  }

  heal(src, tgt, amount) {
    if (!tgt || !tgt.alive || amount <= 0) return 0;
    if (tgt.healCutT > 0) amount *= (1 - tgt.healCut);
    const before = tgt.hp;
    tgt.hp = Math.min(tgt.maxHp, tgt.hp + amount);
    const done = tgt.hp - before;
    if (src) src.healDone += done;
    if (done > 1) this.floatText(tgt, '+' + Math.round(done), 'heal');
    return done;
  }

  kill(u, src) {
    if (!u.alive) return;
    u.alive = false;
    u.hp = 0; u.shields = []; u.shield = 0; u.moving = null; u.target = null;
    this.occ.delete(U.cellKey(u.col, u.row));
    this.fx('death', u, null, '#000');
    for (const h of u.hooks.onDeath) h(u, src);

    const rv = u.revive;
    if (rv && !rv.used && (rv.until === undefined || this.t <= rv.until)) {
      rv.used = true;
      u.pendingRevive = true;
      this.delay(1.5, () => this.respawn(u, rv.pct));
    }
  }

  respawn(u, pct) {
    u.pendingRevive = false;
    const cell = this.freeCellNear(u.homeCol, u.homeRow);
    if (!cell) return;
    u.alive = true;
    u.hp = Math.max(1, u.maxHp * pct);
    u.mana = 0; u.stunT = 0; u.casting = 0; u.attackTimer = 0;
    u.burns = []; u.rend = 0; u.shredMr = 0;
    this.place(u, cell[0], cell[1]);
    this.fx('revive', u, null, '#8fffc0');
    this.floatText(u, 'RISEN', 'heal');
  }

  reviveBest(teamId, pct) {
    const dead = this.teams[teamId].filter(u => !u.alive && !u.pendingRevive);
    if (!dead.length) return;
    dead.sort((a, b) => (b.champ.cost * b.star) - (a.champ.cost * a.star));
    const u = dead[0];
    u.pendingRevive = true;
    this.respawn(u, pct);
  }

  grantMassRevive(teamId, pct, dur) {
    for (const u of this.teams[teamId]) {
      u.revive = { pct, used: false, until: this.t + dur };
    }
  }

  /* ---------------- movement ---------------- */
  acquire(u) {
    const foes = this.livingEnemies(u.team);
    if (!foes.length) { u.target = null; return null; }
    let best = null, bestD = 1e9;
    for (const f of foes) {
      const d = this.dist(u, f) * 100 + f.hp / 1000;
      if (d < bestD) { bestD = d; best = f; }
    }
    u.target = best;
    return best;
  }

  /** first step of a BFS path from u toward target's hex */
  stepToward(u, target) {
    const goalKey = U.cellKey(target.col, target.row);
    const startKey = U.cellKey(u.col, u.row);
    const prev = new Map();
    const q = [[u.col, u.row]];
    prev.set(startKey, null);
    let found = null;
    while (q.length) {
      const [c, r] = q.shift();
      if (U.hexDist(c, r, target.col, target.row) <= u.range && !(c === u.col && r === u.row)) { found = [c, r]; break; }
      for (const n of U.hexNeighbors(c, r)) {
        const k = U.cellKey(n[0], n[1]);
        if (prev.has(k)) continue;
        if (k !== goalKey && this.occ.has(k)) continue;
        prev.set(k, [c, r]);
        q.push(n);
      }
    }
    if (!found) {
      // fall back: greedy adjacent step
      const opts = U.hexNeighbors(u.col, u.row).filter(n => this.cellFree(n[0], n[1]));
      if (!opts.length) return null;
      opts.sort((a, b) => U.hexDist(a[0], a[1], target.col, target.row) - U.hexDist(b[0], b[1], target.col, target.row));
      return opts[0];
    }
    // walk back to the first step
    let cur = found;
    while (true) {
      const p = prev.get(U.cellKey(cur[0], cur[1]));
      if (!p) return null;
      if (p[0] === u.col && p[1] === u.row) return cur;
      cur = p;
    }
  }

  startMove(u, cell) {
    if (!this.cellFree(cell[0], cell[1])) return;
    const from = U.hexPos(u.col, u.row);
    const to = U.hexPos(cell[0], cell[1]);
    this.occ.delete(U.cellKey(u.col, u.row));
    this.occ.set(U.cellKey(cell[0], cell[1]), u);
    u.moving = { fx: from.x, fy: from.y, tx: to.x, ty: to.y, col: cell[0], row: cell[1], t: 0, dur: MOVE_TIME };
  }

  /* ---------------- main loop ---------------- */
  step() {
    if (this.done) return;
    const dt = TICK;
    this.t += dt;

    // scheduled callbacks
    if (this.events.length) {
      const ready = this.events.filter(e => e.t <= this.t);
      if (ready.length) {
        this.events = this.events.filter(e => e.t > this.t);
        for (const e of ready) e.fn();
      }
    }
    for (const tm of this.timers) {
      while (tm.next <= this.t) { tm.fn(); tm.next += tm.interval; }
    }

    for (const u of this.units) {
      if (!u.alive) continue;
      this.tickStatuses(u, dt);
    }
    for (const u of this.units) {
      if (!u.alive) continue;
      this.tickUnit(u, dt);
    }

    // end conditions
    const a = this.teams[0].some(u => u.alive || u.pendingRevive);
    const b = this.teams[1].some(u => u.alive || u.pendingRevive);
    if (!a || !b || this.t >= COMBAT_TIME_LIMIT) {
      this.done = true;
      if (a && !b) this.winner = 0;
      else if (b && !a) this.winner = 1;
      else if (!a && !b) this.winner = -1;
      else {
        const sa = this.teamScore(0), sb = this.teamScore(1);
        this.winner = sa > sb ? 0 : (sb > sa ? 1 : -1);
      }
    }
  }

  teamScore(t) {
    let s = 0;
    for (const u of this.teams[t]) if (u.alive) s += u.hp / u.maxHp + 0.5;
    return s;
  }

  tickStatuses(u, dt) {
    if (u.stunT > 0) u.stunT -= dt;
    if (u.rendT > 0) { u.rendT -= dt; if (u.rendT <= 0) u.rend = 0; }
    if (u.shredMrT > 0) { u.shredMrT -= dt; if (u.shredMrT <= 0) u.shredMr = 0; }
    if (u.healCutT > 0) u.healCutT -= dt;
    if (u.tempOmniT > 0) { u.tempOmniT -= dt; if (u.tempOmniT <= 0) u.tempOmni = 0; }

    for (let i = u.shields.length - 1; i >= 0; i--) {
      u.shields[i].t -= dt;
      if (u.shields[i].t <= 0) u.shields.splice(i, 1);
    }
    u.shield = u.shields.reduce((s, x) => s + x.amt, 0);

    for (let i = u.buffs.length - 1; i >= 0; i--) {
      u.buffs[i].t -= dt;
      if (u.buffs[i].t <= 0) { u[u.buffs[i].stat] /= u.buffs[i].mult; u.buffs.splice(i, 1); }
    }
    for (let i = u.flats.length - 1; i >= 0; i--) {
      u.flats[i].t -= dt;
      if (u.flats[i].t <= 0) { u[u.flats[i].stat] -= u.flats[i].val; u.flats.splice(i, 1); }
    }
    for (let i = u.burns.length - 1; i >= 0; i--) {
      const b = u.burns[i];
      b.t -= dt; b.tick -= dt;
      if (b.tick <= 0) { b.tick = 1; this.damage(b.src, u, u.maxHp * b.pct, 'true'); }
      if (b.t <= 0) u.burns.splice(i, 1);
    }
    for (let i = u.regenQueue.length - 1; i >= 0; i--) {
      const r = u.regenQueue[i];
      const give = r.amt * (dt / r.t);
      this.heal(null, u, Math.min(r.amt, give));
      r.amt -= give; r.t -= dt;
      if (r.t <= 0 || r.amt <= 0) u.regenQueue.splice(i, 1);
    }
    if (u.itemRegen) this.heal(null, u, u.maxHp * u.itemRegen * dt);
    if (u.regen) {
      const amt = u.maxHp * u.regen.pct * dt;
      const missing = u.maxHp - u.hp;
      const healed = this.heal(null, u, Math.min(amt, missing));
      const over = amt - healed;
      if (over > 0) {
        const cap = u.maxHp * u.regen.cap;
        const cur = u.shields.filter(s => s.tide).reduce((a, b) => a + b.amt, 0);
        if (cur < cap) {
          let sh = u.shields.find(s => s.tide);
          if (!sh) { sh = { amt: 0, t: 999, tide: true }; u.shields.push(sh); }
          sh.amt = Math.min(cap, sh.amt + over);
          u.shield = u.shields.reduce((s, x) => s + x.amt, 0);
        }
      }
    }
    if (u.manaRegen && !u.casting) u.mana = Math.min(u.maxMana, u.mana + u.manaRegen * dt);
  }

  tickUnit(u, dt) {
    // movement animation
    if (u.moving) {
      u.moving.t += dt;
      const k = Math.min(1, u.moving.t / u.moving.dur);
      u.x = u.moving.fx + (u.moving.tx - u.moving.fx) * k;
      u.y = u.moving.fy + (u.moving.ty - u.moving.fy) * k;
      if (k >= 1) { u.col = u.moving.col; u.row = u.moving.row; u.moving = null; }
      return;
    }
    if (u.stunT > 0) return;

    // casting
    if (u.casting > 0) {
      u.casting -= dt;
      if (u.casting <= 0) {
        u.casting = 0;
        u.mana = 0;
        try { u.champ.ab.cast(this, u, u.champ.ab.vals); } catch (err) { /* keep the battle going */ }
        for (const h of u.hooks.onCast) h(u);
      }
      return;
    }
    if (u.maxMana > 0 && u.mana >= u.maxMana) {
      u.casting = CAST_TIME;
      this.fx('cast', u, null, '#7fe3ff');
      return;
    }

    let t = u.target;
    if (!t || !t.alive) t = this.acquire(u);
    if (!t) return;

    const d = this.dist(u, t);
    if (d <= u.range) {
      u.attackTimer -= dt;
      if (u.attackTimer <= 0) {
        u.attackTimer = 1 / Math.min(u.as, AS_CAP);
        this.attack(u, t);
      }
    } else {
      const cell = this.stepToward(u, t);
      if (cell) this.startMove(u, cell);
      else { u.attackTimer = Math.max(u.attackTimer - dt, 0); this.acquire(u); }
    }
  }

  attack(u, t) {
    if (u.range > 1) this.fx('shot', t, u, '#ffe9c0');
    else this.fx('hit', t, u, '#ffffff');
    if (t.dodge > 0 && Math.random() < t.dodge) {
      this.floatText(t, 'dodge', 'miss');
    } else {
      this.damage(u, t, u.ad, 'physical', { isAttack: true });
    }
    if (u.maxMana > 0 && !u.casting) u.mana = Math.min(u.maxMana, u.mana + 10);
    for (const h of u.hooks.onAttack) h(u, t);
  }

  runToEnd(maxSteps) {
    const cap = maxSteps || Math.ceil(COMBAT_TIME_LIMIT / TICK) + 10;
    let n = 0;
    while (!this.done && n++ < cap) this.step();
    this.done = true;
    return this.winner;
  }

  survivors(teamId) { return this.teams[teamId].filter(u => u.alive); }
}
