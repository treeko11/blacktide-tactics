/* ============================================================
   GAME STATE - economy, shop, pool, rounds, matchmaking
   ============================================================ */
'use strict';

const XP_TABLE = { 1: 2, 2: 2, 3: 6, 4: 10, 5: 20, 6: 36, 7: 56, 8: 80, 9: 1e9 };

const SHOP_ODDS = {
  1: [100, 0, 0, 0, 0],
  2: [100, 0, 0, 0, 0],
  3: [75, 25, 0, 0, 0],
  4: [55, 30, 15, 0, 0],
  5: [45, 33, 20, 2, 0],
  6: [30, 40, 25, 5, 0],
  7: [19, 30, 35, 15, 1],
  8: [17, 24, 32, 24, 3],
  9: [10, 18, 25, 35, 12]
};

const BENCH_SIZE = 9;
const PLAN_TIME = 32;

/* ---------- monsters (never enter the shop: cost 0) ---------- */
const CREEPS = [
  { id: 'rat', name: 'Deck Rat', icon: '\u{1F400}', cost: 0, traits: [], hp: 420, ad: 32, as: 0.6, armor: 15, mr: 15, range: 1, mana: [0, 0] },
  { id: 'crab', name: 'Hull Crab', icon: '\u{1F980}', cost: 0, traits: [], hp: 900, ad: 45, as: 0.5, armor: 40, mr: 25, range: 1, mana: [0, 0] },
  { id: 'gull', name: 'Rot Gull', icon: '\u{1F985}', cost: 0, traits: [], hp: 550, ad: 42, as: 0.7, armor: 15, mr: 15, range: 3, mana: [0, 0] },
  { id: 'serpent', name: 'Reef Serpent', icon: '\u{1F40D}', cost: 0, traits: [], hp: 1300, ad: 70, as: 0.65, armor: 45, mr: 45, range: 2, mana: [0, 0] },
  { id: 'skiff', name: 'Ghost Skiff', icon: '\u{1F6F6}', cost: 0, traits: [], hp: 1100, ad: 65, as: 0.7, armor: 35, mr: 55, range: 4, mana: [0, 0] },
  { id: 'golem', name: 'Wreck Golem', icon: '\u{1F5FF}', cost: 0, traits: [], hp: 3200, ad: 110, as: 0.55, armor: 70, mr: 70, range: 1, mana: [0, 0] },
  { id: 'elder', name: 'Elder Kraken', icon: '\u{1F419}', cost: 0, traits: [], hp: 6000, ad: 160, as: 0.7, armor: 90, mr: 90, range: 2, mana: [0, 0] }
];
for (const c of CREEPS) {
  c.ab = { name: '-', desc: '', vals: {}, cast() {} };
  CHAMP_BY_ID[c.id] = c;
}

const Game = {
  stage: 1, round: 1,
  phase: 'plan',
  timer: PLAN_TIME,
  pool: {},
  player: null,
  bots: [],
  shop: [],
  shopLocked: false,
  sim: null,
  currentOpponent: null,
  lastOpponentIdx: -1,
  logLines: [],
  onChange: null,
  speed: 1,
  pendingResult: null,

  /* =============== setup =============== */
  init() {
    this.pool = {};
    this.shop = [];                 // drop the old shop before rebuilding the pool
    this.sim = null;
    this.currentOpponent = null;
    this.lastOpponentIdx = -1;
    this.armoryOffer = null;
    for (const c of CHAMPIONS) this.pool[c.id] = POOL_SIZE[c.cost];
    this.player = {
      name: 'You', icon: '\u{1F9ED}', isBot: false, hp: 100, gold: 2, level: 1, xp: 0,
      streak: 0, lastResult: 0, alive: true, place: 0,
      board: [], bench: new Array(BENCH_SIZE).fill(null), items: []
    };
    this.bots = makeBots(7);
    this.stage = 1; this.round = 1;
    this.shopLocked = false;
    this.logLines = [];
    this.log('The fleet sets out. Eight captains, one horizon.');
    this.refreshShop(true);
    this.beginPlanning();
  },

  everyone() { return [this.player].concat(this.bots); },
  alivePlayers() { return this.everyone().filter(p => p.alive); },

  log(txt, cls) {
    this.logLines.unshift({ txt, cls: cls || '' });
    if (this.logLines.length > 60) this.logLines.pop();
  },

  /* =============== pool =============== */
  takeFromPool(id) {
    if ((this.pool[id] || 0) <= 0) return false;
    this.pool[id]--; return true;
  },
  returnToPool(id, star) {
    if (!(id in this.pool)) return;
    this.pool[id] += Math.pow(3, (star || 1) - 1);
  },
  returnOffers(ids) { for (const id of ids) if (id) this.returnToPool(id, 1); },

  poolByCost(cost) {
    const out = [];
    for (const c of CHAMPIONS) if (c.cost === cost && this.pool[c.id] > 0) out.push(c.id);
    return out;
  },

  /** draws 5 cards, removing them from the shared pool */
  rollShop(level) {
    const odds = SHOP_ODDS[U.clamp(level, 1, 9)];
    const out = [];
    for (let i = 0; i < 5; i++) {
      let id = null;
      for (let attempt = 0; attempt < 8 && !id; attempt++) {
        const cost = U.weighted(odds.map((w, idx) => [idx + 1, w])) ;
        const avail = this.poolByCost(cost);
        if (!avail.length) continue;
        // weight by how many copies remain
        const table = avail.map(cid => [cid, this.pool[cid]]);
        id = U.weighted(table);
      }
      if (!id) { // desperate fallback
        for (let cost = 1; cost <= 5 && !id; cost++) {
          const avail = this.poolByCost(cost);
          if (avail.length) id = U.pick(avail);
        }
      }
      if (id) { this.pool[id]--; out.push(id); }
    }
    return out;
  },

  refreshShop(free) {
    if (!free) { /* caller pays */ }
    this.returnOffers(this.shop);
    this.shop = this.rollShop(this.player.level);
  },

  /* =============== player actions =============== */
  reroll() {
    if (this.phase !== 'plan' || this.player.gold < 2) return false;
    this.player.gold -= 2;
    this.refreshShop();
    this.changed(); return true;
  },

  buyXp() {
    if (this.phase !== 'plan' || this.player.gold < 4 || this.player.level >= 9) return false;
    this.player.gold -= 4;
    this.giveXp(this.player, 4);
    this.changed(); return true;
  },

  giveXp(p, n) {
    p.xp += n;
    while (p.level < 9 && p.xp >= XP_TABLE[p.level]) { p.xp -= XP_TABLE[p.level]; p.level++; }
    if (p.level >= 9) p.xp = Math.min(p.xp, XP_TABLE[8]);
  },

  benchFreeIndex() { return this.player.bench.indexOf(null); },
  ownedUnits() { return this.player.board.concat(this.player.bench.filter(Boolean)); },

  buy(index) {
    if (this.phase !== 'plan') return false;
    const id = this.shop[index];
    if (!id) return false;
    const champ = CHAMP_BY_ID[id];
    if (this.player.gold < champ.cost) { this.flash('Not enough gold'); return false; }
    // room? either a bench slot, or it completes an upgrade
    const slot = this.benchFreeIndex();
    const copies = this.ownedUnits().filter(u => u.champId === id && u.star === 1).length;
    if (slot < 0 && copies < 2) { this.flash('Deck is full'); return false; }
    this.player.gold -= champ.cost;
    this.shop[index] = null;
    const unit = { uid: U.uid(), champId: id, star: 1, items: [] };
    if (slot >= 0) this.player.bench[slot] = unit;
    else this.player.bench.push(unit);   // temporary overflow, resolved by the merge below
    this.checkUpgrades();
    if (this.player.bench.length > BENCH_SIZE) this.player.bench.length = BENCH_SIZE;
    this.changed(); return true;
  },

  sell(unit) {
    if (this.phase !== 'plan') return false;
    const value = CHAMP_BY_ID[unit.champId].cost * Math.pow(3, unit.star - 1);
    this.player.gold += value;
    this.returnToPool(unit.champId, unit.star);
    for (const it of unit.items) this.player.items.push(it);
    this.removeUnit(unit);
    this.changed(); return true;
  },

  removeUnit(unit) {
    const bi = this.player.bench.indexOf(unit);
    if (bi >= 0) { this.player.bench[bi] = null; return; }
    const i = this.player.board.indexOf(unit);
    if (i >= 0) this.player.board.splice(i, 1);
  },

  /** merge any three matching copies into the next star */
  checkUpgrades() {
    let merged = true;
    while (merged) {
      merged = false;
      for (let star = 1; star <= 2 && !merged; star++) {
        const groups = {};
        for (const u of this.ownedUnits()) {
          if (u.star !== star) continue;
          (groups[u.champId] = groups[u.champId] || []).push(u);
        }
        for (const id in groups) {
          if (groups[id].length < 3) continue;
          const three = groups[id].slice(0, 3);
          // keep the board seat if one of them was fielded
          const onBoard = three.find(u => this.player.board.indexOf(u) >= 0);
          const items = [];
          for (const u of three) items.push(...u.items);
          const keepPos = onBoard ? { col: onBoard.col, row: onBoard.row } : null;
          for (const u of three) this.removeUnit(u);
          const up = { uid: U.uid(), champId: id, star: star + 1, items: items.slice(0, 3) };
          for (const extra of items.slice(3)) this.player.items.push(extra);
          if (keepPos) { up.col = keepPos.col; up.row = keepPos.row; this.player.board.push(up); }
          else {
            const slot = this.benchFreeIndex();
            if (slot >= 0) this.player.bench[slot] = up; else this.player.bench.push(up);
          }
          this.log((star === 1 ? '★★ ' : '★★★ ') + CHAMP_BY_ID[id].name + '!', 'good');
          merged = true;
          break;
        }
      }
    }
  },

  boardCap() { return this.player.level; },
  boardCount() { return this.player.board.length; },

  cellOccupant(col, row) { return this.player.board.find(u => u.col === col && u.row === row) || null; },

  /** move/swap a unit between bench slots and board cells */
  moveUnit(unit, dest) {
    if (this.phase !== 'plan') return false;
    const fromBench = this.player.bench.indexOf(unit) >= 0;

    if (dest.type === 'bench') {
      const occ = this.player.bench[dest.index];
      if (occ === unit) return false;
      if (fromBench) {
        const i = this.player.bench.indexOf(unit);
        this.player.bench[i] = occ; this.player.bench[dest.index] = unit;
      } else {
        if (occ) {
          // swap board unit with bench unit
          const col = unit.col, row = unit.row;
          this.player.board.splice(this.player.board.indexOf(unit), 1);
          occ.col = col; occ.row = row;
          this.player.board.push(occ);
          this.player.bench[dest.index] = unit;
          delete unit.col; delete unit.row;
        } else {
          this.player.board.splice(this.player.board.indexOf(unit), 1);
          this.player.bench[dest.index] = unit;
          delete unit.col; delete unit.row;
        }
      }
    } else { // board cell
      if (dest.row < BOARD.PLAYER_ROW_MIN) return false;
      const occ = this.cellOccupant(dest.col, dest.row);
      if (occ === unit) return false;
      if (fromBench && !occ && this.boardCount() >= this.boardCap()) { this.flash('Crew is at capacity'); return false; }
      if (fromBench) {
        const i = this.player.bench.indexOf(unit);
        this.player.bench[i] = null;
        if (occ) {
          this.player.board.splice(this.player.board.indexOf(occ), 1);
          this.player.bench[i] = occ;
          delete occ.col; delete occ.row;
        }
        unit.col = dest.col; unit.row = dest.row;
        this.player.board.push(unit);
      } else {
        if (occ) { occ.col = unit.col; occ.row = unit.row; }
        unit.col = dest.col; unit.row = dest.row;
      }
    }
    this.changed(); return true;
  },

  /* ---------- items ---------- */
  giveItem(id) { this.player.items.push(id); },

  equipItem(itemId, unit) {
    if (this.phase !== 'plan') return false;
    const idx = this.player.items.indexOf(itemId);
    if (idx < 0) return false;
    if (isComponent(itemId)) {
      const partner = unit.items.find(i => isComponent(i));
      if (partner) {
        const forged = combineItems(itemId, partner);
        if (forged) {
          unit.items[unit.items.indexOf(partner)] = forged;
          this.player.items.splice(idx, 1);
          this.log('Forged ' + ITEMS[forged].name, 'good');
          this.changed(); return true;
        }
      }
    }
    if (unit.items.length >= 3) { this.flash('That unit is carrying three items'); return false; }
    unit.items.push(itemId);
    this.player.items.splice(idx, 1);
    this.changed(); return true;
  },

  /* =============== traits =============== */
  traitCounts(board) {
    const seen = {};
    for (const u of board) {
      const c = CHAMP_BY_ID[u.champId];
      for (const t of c.traits) { (seen[t] = seen[t] || new Set()).add(u.champId); }
    }
    const out = [];
    for (const t in seen) out.push({ id: t, count: seen[t].size, ti: traitTierIdx(TRAITS[t], seen[t].size) });
    out.sort((a, b) => (b.ti - a.ti) || (b.count - a.count) || a.id.localeCompare(b.id));
    return out;
  },

  /* =============== round flow =============== */
  roundType() {
    if (this.stage === 1) return this.round <= 3 ? 'pve' : 'armory';
    if (this.round === 3) return 'pve';
    if (this.round === 6) return 'armory';
    return 'pvp';
  },
  roundsThisStage() { return this.stage === 1 ? 4 : 6; },

  beginPlanning() {
    this.phase = 'plan';
    this.timer = PLAN_TIME;
    if (this.roundType() === 'armory') { this.openArmory(); return; }
    this.changed();
  },

  /* ---------- armory ---------- */
  openArmory() {
    this.phase = 'armory';
    const list = U.shuffle(forgedList()).slice(0, 3);
    this.armoryOffer = list;
    this.player.gold += 2;
    this.changed();
  },
  takeArmory(id) {
    if (this.phase !== 'armory') return;
    this.giveItem(id);
    this.log('Hauled ' + ITEMS[id].name + ' from the armoury.', 'good');
    this.armoryOffer = null;
    this.advanceRound();
  },

  /* ---------- creep waves ---------- */
  creepWave() {
    const s = this.stage, seats = [[3, 5], [2, 5], [4, 5], [3, 4], [1, 5], [5, 5], [2, 4], [4, 4], [3, 6]];
    const wave = [];
    const add = (id, star, n) => { for (let i = 0; i < n; i++) wave.push({ champId: id, star: star, items: [] }); };
    if (s === 1) {
      if (this.round === 1) add('rat', 1, 3);
      else if (this.round === 2) { add('rat', 1, 3); add('gull', 1, 1); }
      else { add('crab', 1, 2); add('rat', 1, 3); }
    } else if (s === 2) { add('crab', 2, 2); add('gull', 2, 3); }
    else if (s === 3) { add('serpent', 2, 2); add('skiff', 2, 2); add('crab', 2, 2); }
    else if (s === 4) { add('golem', 1, 1); add('serpent', 2, 3); }
    else if (s === 5) { add('golem', 2, 2); add('skiff', 3, 2); }
    else if (s === 6) { add('elder', 1, 1); add('golem', 2, 2); }
    else { add('elder', 2, 1); add('golem', 3, 2); add('serpent', 3, 2); }
    return wave.slice(0, 9).map((w, i) => ({ champId: w.champId, star: w.star, items: [], col: seats[i][0], row: seats[i][1] }));
  },

  creepName() {
    const s = this.stage;
    if (s === 1) return 'Bilge Vermin';
    if (s === 2) return 'Gull Flock';
    if (s === 3) return 'Reef Ambush';
    if (s === 4) return 'The Wreck';
    if (s === 5) return 'Drowned Armada';
    return 'The Elder Deep';
  },

  /* ---------- combat ---------- */
  startCombat() {
    if (this.phase !== 'plan') return;
    if (!this.player.board.length) { /* still allowed - you will simply lose */ }
    this.phase = 'combat';

    const type = this.roundType();
    let oppBoard, oppName, oppIcon, oppRef = null;

    if (type === 'pve') {
      oppBoard = this.creepWave();
      oppName = this.creepName(); oppIcon = '\u{1F480}';
    } else {
      const foes = this.bots.filter(b => b.alive);
      let pick = foes.filter(b => b.idx !== this.lastOpponentIdx);
      if (!pick.length) pick = foes;
      oppRef = U.pick(pick);
      this.lastOpponentIdx = oppRef ? oppRef.idx : -1;
      oppBoard = oppRef ? oppRef.getBoard() : [];
      oppName = oppRef ? oppRef.name : 'A ghost ship';
      oppIcon = oppRef ? oppRef.icon : '\u{1F47B}';
    }

    this.currentOpponent = { name: oppName, icon: oppIcon, ref: oppRef, isCreep: type === 'pve' };
    const myBoard = this.player.board.map(u => ({ champId: u.champId, star: u.star, items: u.items, col: u.col, row: u.row }));
    this.sim = new Sim(myBoard, oppBoard, { render: true });
    this.changed();
  },

  /** called by the UI when the rendered sim finishes */
  resolveCombat() {
    const sim = this.sim;
    const win = sim.winner === 0;
    const type = this.roundType();
    const surv = sim.survivors(1);

    let dmg = 0;
    if (!win) {
      dmg = this.stageDamage();
      for (const u of surv) dmg += (u.star || 1) + (u.champ.cost >= 4 ? 1 : 0);
    }

    const p = this.player;
    if (win) {
      p.streak = p.streak >= 0 ? p.streak + 1 : 1;
      p.lastResult = 1;
      p.gold += 1;
      this.log('Victory over ' + this.currentOpponent.name + '.', 'good');
      if (type === 'pve') this.pveLoot();
    } else if (sim.winner === 1) {
      p.streak = p.streak <= 0 ? p.streak - 1 : -1;
      p.lastResult = -1;
      p.hp -= dmg;
      this.log('Boarded by ' + this.currentOpponent.name + '. –' + dmg + ' hull.', 'bad');
    } else {
      p.lastResult = 0;
      p.hp -= Math.max(1, Math.floor(this.stageDamage() / 2));
      this.log('The fight ends in a stalemate.', '');
    }

    if (this.currentOpponent.ref) {
      const b = this.currentOpponent.ref;
      if (win) {
        b.streak = b.streak <= 0 ? -1 : b.streak - 1;
        b.lastResult = -1;
        let bd = this.stageDamage();
        for (const u of sim.survivors(0)) bd += (u.star || 1) + (u.champ.cost >= 4 ? 1 : 0);
        b.hp -= bd;
      } else {
        b.streak = b.streak >= 0 ? b.streak + 1 : 1;
        b.lastResult = 1;
      }
    }

    this.resolveBotFights();
    this.checkEliminations();
    this.phase = 'result';
    this.pendingResult = { win, dmg, opp: this.currentOpponent, draw: sim.winner === -1 };
    this.changed();
  },

  stageDamage() {
    const t = [0, 0, 2, 3, 5, 7, 9, 11, 14];
    return t[Math.min(this.stage, 8)];
  },

  pveLoot() {
    const drops = [];
    const n = (this.stage === 1) ? 1 : (Math.random() < 0.5 ? 1 : 2);
    for (let i = 0; i < n; i++) drops.push(U.pick(COMPONENTS));
    for (const d of drops) this.giveItem(d);
    const gold = 2 + U.randInt(3);
    this.player.gold += gold;
    this.log('Salvage: ' + drops.map(d => ITEMS[d].name).join(', ') + ' and ' + gold + ' gold.', 'good');
  },

  /** bots that did not fight the player fight each other, headless */
  resolveBotFights() {
    if (this.roundType() === 'pve') {
      for (const b of this.bots) {
        if (!b.alive) continue;
        const sim = new Sim(b.getBoard(), this.creepWave(), {});
        sim.runToEnd();
        if (sim.winner !== 0) {
          let d = this.stageDamage();
          for (const u of sim.survivors(1)) d += (u.star || 1);
          b.hp -= d;
          b.lastResult = -1; b.streak = b.streak <= 0 ? b.streak - 1 : -1;
        } else { b.lastResult = 1; b.streak = b.streak >= 0 ? b.streak + 1 : 1; b.gold += 1; }
      }
      return;
    }
    const busy = this.currentOpponent && this.currentOpponent.ref ? this.currentOpponent.ref : null;
    const pool = U.shuffle(this.bots.filter(b => b.alive && b !== busy));
    while (pool.length >= 2) {
      const a = pool.pop(), b = pool.pop();
      const sim = new Sim(a.getBoard(), b.getBoard(), {});
      sim.runToEnd();
      const winA = sim.winner === 0;
      const loser = winA ? b : a, winner = winA ? a : b;
      if (sim.winner === -1) {
        a.hp -= 2; b.hp -= 2; a.lastResult = 0; b.lastResult = 0;
        continue;
      }
      let d = this.stageDamage();
      for (const u of sim.survivors(winA ? 0 : 1)) d += (u.star || 1) + (u.champ.cost >= 4 ? 1 : 0);
      loser.hp -= d;
      loser.lastResult = -1; loser.streak = loser.streak <= 0 ? loser.streak - 1 : -1;
      winner.lastResult = 1; winner.streak = winner.streak >= 0 ? winner.streak + 1 : 1; winner.gold += 1;
    }
    // odd bot out gets a bye
    if (pool.length === 1) pool[0].lastResult = 0;
  },

  checkEliminations() {
    const dying = this.everyone().filter(p => p.alive && p.hp <= 0);
    if (!dying.length) return;
    const after = this.everyone().filter(p => p.alive && p.hp > 0).length;
    dying.sort((a, b) => a.hp - b.hp);          // the most battered sinks first
    dying.forEach((p, i) => {
      p.alive = false; p.hp = 0;
      p.place = after + dying.length - i;
      this.log(p.name + ' goes down with the ship — ' + this.ordinal(p.place) + '.', p.isBot ? '' : 'bad');
    });
  },

  ordinal(n) {
    const s = ['th', 'st', 'nd', 'rd'], v = n % 100;
    return n + (s[(v - 20) % 10] || s[v] || s[0]);
  },

  /* ---------- economy between rounds ---------- */
  advanceRound(skipIncome) {
    if (!this.player.alive || this.alivePlayers().length <= 1) { this.endGame(); return; }

    this.round++;
    if (this.round > this.roundsThisStage()) { this.round = 1; this.stage++; }

    if (!skipIncome) {
      const p = this.player;
      let inc = 5;
      inc += Math.min(5, Math.floor(p.gold / 10));
      const st = Math.abs(p.streak);
      inc += st >= 5 ? 3 : st >= 4 ? 2 : st >= 2 ? 1 : 0;
      p.gold += inc;
      this.giveXp(p, 2);
      this.lastIncome = inc;
      for (const b of this.bots) if (b.alive) b.takeTurn();
    }

    if (!this.shopLocked) this.refreshShop(true);
    this.beginPlanning();
  },

  endGame() {
    this.phase = 'over';
    const me = this.player;
    me.place = me.alive ? 1 : (me.place || this.alivePlayers().length + 1);
    this.changed();
  },

  flash(msg) { this.flashMsg = msg; this.flashT = 2; if (this.onChange) this.onChange('flash'); },
  changed() { if (this.onChange) this.onChange(); }
};
