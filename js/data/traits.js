/* ============================================================
   TRAITS - Origins (where they hail from) & Classes (what they do)
   Each trait: breaks[] = unit counts, vals = tier-scaled numbers,
   apply(ctx) runs at combat start.
   ctx = {sim, team, holders, ti, count, teamId}
   ============================================================ */
'use strict';

/* small stat helpers used by traits + items */
function addStat(u, key, val) { u[key] = (u[key] || 0) + val; }
function addMaxHp(u, val) { u.maxHp += val; u.hp += val; }

const TRAITS = {

  /* ---------------- ORIGINS ---------------- */

  corsair: {
    name: 'Corsair', icon: '\u{1F3F4}', kind: 'origin', breaks: [2, 4, 6],
    desc: 'Plunder fuels the crew. Your team gains {teamAd}% Attack Damage. Corsairs gain double, plus {crit}% Critical Strike Chance.',
    vals: { teamAd: [10, 22, 40], crit: [15, 25, 40] },
    apply(c) {
      const v = this.vals, i = c.ti;
      for (const u of c.team) u.ad *= (1 + v.teamAd[i] / 100);
      for (const u of c.holders) { u.ad *= (1 + v.teamAd[i] / 100); addStat(u, 'crit', v.crit[i] / 100); }
    }
  },

  leviathan: {
    name: 'Leviathan', icon: '\u{1F419}', kind: 'origin', breaks: [2, 3, 4],
    desc: 'Things older than ships. Leviathans gain {hp} Health and take {dr}% reduced damage.',
    vals: { hp: [500, 1000, 1900], dr: [8, 14, 24] },
    apply(c) {
      const v = this.vals, i = c.ti;
      for (const u of c.holders) { addMaxHp(u, v.hp[i]); addStat(u, 'dr', v.dr[i] / 100); }
    }
  },

  siren: {
    name: 'Siren', icon: '\u{1F9DC}', kind: 'origin', breaks: [2, 4, 6],
    desc: 'Songs that drown men. Your team gains {teamAp} Ability Power. Sirens gain {ap} instead and refund {mana} Mana after casting.',
    vals: { teamAp: [10, 20, 35], ap: [30, 60, 110], mana: [10, 20, 30] },
    apply(c) {
      const v = this.vals, i = c.ti;
      for (const u of c.team) u.ap += v.teamAp[i];
      for (const u of c.holders) {
        u.ap += (v.ap[i] - v.teamAp[i]);
        u.hooks.onCast.push(function (self) { self.mana = Math.min(self.maxMana, self.mana + v.mana[i]); });
      }
    }
  },

  ghost: {
    name: 'Ghost Fleet', icon: '\u{1F480}', kind: 'origin', breaks: [2, 4, 6],
    desc: 'The drowned do not stay down. The first time a Ghost Fleet unit would die it returns after 1.5s with {hp}% Health. At 6, every ally rises once at 30%.',
    vals: { hp: [35, 55, 80] },
    apply(c) {
      const v = this.vals, i = c.ti;
      for (const u of c.holders) u.revive = { pct: v.hp[i] / 100, used: false };
      if (c.count >= 6) for (const u of c.team) if (!u.revive) u.revive = { pct: 0.30, used: false };
    }
  },

  tidecaller: {
    name: 'Tidecaller', icon: '\u{1F30A}', kind: 'origin', breaks: [2, 3, 4],
    desc: 'The tide mends what steel breaks. Your team heals {hps}% max Health per second. Overhealing becomes a shield, up to {cap}% max Health.',
    vals: { hps: [1.2, 2.2, 4], cap: [10, 15, 25] },
    apply(c) {
      const v = this.vals, i = c.ti;
      for (const u of c.team) u.regen = { pct: v.hps[i] / 100, cap: v.cap[i] / 100 };
    }
  },

  stormborn: {
    name: 'Stormborn', icon: '⚡', kind: 'origin', breaks: [2, 4, 6],
    desc: 'Every 3 seconds, lightning strikes the {n} highest-Health enemies for {dmg} magic damage.',
    vals: { n: [1, 2, 4], dmg: [180, 380, 850] },
    apply(c) {
      const v = this.vals, i = c.ti, sim = c.sim, tid = c.teamId;
      sim.addTimer(3, 3, function () {
        const foes = sim.livingEnemies(tid);
        foes.sort((a, b) => b.hp - a.hp);
        for (let k = 0; k < Math.min(v.n[i], foes.length); k++) {
          sim.fx('bolt', foes[k]);
          sim.damage(null, foes[k], v.dmg[i], 'magic');
        }
      });
    }
  },

  navy: {
    name: 'Royal Navy', icon: '⚓', kind: 'origin', breaks: [2, 3, 4, 5],
    desc: 'Discipline holds the line. Your team gains {res} Armor and Magic Resist. Royal Navy units gain double, and recover {heal}% of damage taken over 3s.',
    vals: { res: [15, 30, 55, 95], heal: [15, 22, 32, 50] },
    apply(c) {
      const v = this.vals, i = c.ti;
      for (const u of c.team) { addStat(u, 'armor', v.res[i]); addStat(u, 'mr', v.res[i]); }
      for (const u of c.holders) {
        addStat(u, 'armor', v.res[i]); addStat(u, 'mr', v.res[i]);
        u.hooks.onDamaged.push(function (self, amt) { self.regenQueue.push({ amt: amt * v.heal[i] / 100, t: 3 }); });
      }
    }
  },

  /* ---------------- CLASSES ---------------- */

  gunner: {
    name: 'Gunner', icon: '\u{1F52B}', kind: 'class', breaks: [2, 4, 6],
    desc: 'Every third attack, Gunners unload {n} extra shots at nearby enemies for {dmg}% Attack Damage.',
    vals: { n: [2, 3, 5], dmg: [45, 60, 80] },
    apply(c) {
      const v = this.vals, i = c.ti, sim = c.sim;
      for (const u of c.holders) {
        u.gunCount = 0;
        u.hooks.onAttack.push(function (self) {
          self.gunCount++;
          if (self.gunCount % 3 !== 0) return;
          const pool = sim.livingEnemies(self.team);
          if (!pool.length) return;
          pool.sort((a, b) => sim.dist(self, a) - sim.dist(self, b));
          for (let k = 0; k < v.n[i]; k++) {
            const t = pool[k % pool.length];
            sim.fx('tracer', t, self, '#ffd27a');
            sim.damage(self, t, self.ad * v.dmg[i] / 100, 'physical');
          }
        });
      }
    }
  },

  swash: {
    name: 'Swashbuckler', icon: '\u{1F5E1}', kind: 'class', breaks: [2, 4, 6],
    desc: 'Swashbucklers gain {as}% Attack Speed per attack, stacking 8 times, and have {dodge}% chance to dodge attacks.',
    vals: { as: [5, 9, 15], dodge: [10, 18, 30] },
    apply(c) {
      const v = this.vals, i = c.ti;
      for (const u of c.holders) {
        addStat(u, 'dodge', v.dodge[i] / 100);
        u.swashStacks = 0;
        u.hooks.onAttack.push(function (self) {
          if (self.swashStacks >= 8) return;
          self.swashStacks++; self.as *= (1 + v.as[i] / 100);
        });
      }
    }
  },

  bosun: {
    name: 'Bosun', icon: '\u{1F4AA}', kind: 'class', breaks: [2, 4, 6],
    desc: 'Bosuns gain {hp} Health. Your other units gain {team} Health.',
    vals: { hp: [350, 750, 1400], team: [0, 150, 350] },
    apply(c) {
      const v = this.vals, i = c.ti;
      if (v.team[i]) for (const u of c.team) addMaxHp(u, v.team[i]);
      for (const u of c.holders) addMaxHp(u, v.hp[i]);
    }
  },

  harpooner: {
    name: 'Harpooner', icon: '\u{1FA9D}', kind: 'class', breaks: [2, 4, 6],
    desc: 'Harpooner attacks Rend for 6s, reducing Armor by {shred}%. They deal {bonus}% bonus true damage to Rent enemies.',
    vals: { shred: [20, 30, 45], bonus: [8, 15, 28] },
    apply(c) {
      const v = this.vals, i = c.ti, sim = c.sim;
      for (const u of c.holders) {
        u.hooks.onAttack.push(function (self, tgt) {
          if (!tgt || !tgt.alive) return;
          if (tgt.rend > 0) sim.damage(self, tgt, self.ad * v.bonus[i] / 100, 'true');
          sim.applyShred(tgt, v.shred[i] / 100, 6);
        });
      }
    }
  },

  navigator: {
    name: 'Navigator', icon: '\u{1F9ED}', kind: 'class', breaks: [2, 3, 4],
    desc: 'Your team starts with {start} Mana and gains {reg} Mana per second. Navigators also gain {as}% Attack Speed.',
    vals: { start: [15, 30, 50], reg: [3, 6, 10], as: [15, 25, 45] },
    apply(c) {
      const v = this.vals, i = c.ti;
      for (const u of c.team) { u.mana = Math.min(u.maxMana, u.mana + v.start[i]); addStat(u, 'manaRegen', v.reg[i]); }
      for (const u of c.holders) u.as *= (1 + v.as[i] / 100);
    }
  },

  reaver: {
    name: 'Reaver', icon: '\u{1FA78}', kind: 'class', breaks: [2, 4, 6],
    desc: 'Reavers gain {ov}% Omnivamp and deal {bonus}% bonus damage to enemies below half Health.',
    vals: { ov: [12, 22, 40], bonus: [15, 28, 50] },
    apply(c) {
      const v = this.vals, i = c.ti;
      for (const u of c.holders) {
        addStat(u, 'omnivamp', v.ov[i] / 100);
        addStat(u, 'executeAmp', v.bonus[i] / 100);
      }
    }
  }
};

for (const k in TRAITS) TRAITS[k].id = k;

/** index of highest reached breakpoint, or -1 */
function traitTierIdx(trait, count) {
  let idx = -1;
  for (let i = 0; i < trait.breaks.length; i++) if (count >= trait.breaks[i]) idx = i;
  return idx;
}

/** style tier for the manifest panel */
function traitTierClass(trait, idx) {
  if (idx < 0) return 'off';
  if (trait.breaks.length <= 3) return ['bronze', 'silver', 'gold'][idx] || 'gold';
  return ['bronze', 'silver', 'gold', 'prism'][idx] || 'prism';
}
