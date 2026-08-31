/* ============================================================
   ITEMS - 5 components, 15 forged items (every pair)
   apply(u, sim) is called once at combat start.
   ============================================================ */
'use strict';

const COMPONENTS = ['blade', 'lens', 'plate', 'keg', 'sextant'];

const ITEMS = {

  /* ------------- components ------------- */
  blade: {
    name: "Corsair's Blade", icon: '\u{1F5E1}', comp: true,
    desc: '+10 Attack Damage',
    apply(u) { u.ad += 10; }
  },
  lens: {
    name: 'Sea-Glass Lens', icon: '\u{1F52E}', comp: true,
    desc: '+10 Ability Power',
    apply(u) { u.ap += 10; }
  },
  plate: {
    name: 'Barnacle Plate', icon: '\u{1F6E1}', comp: true,
    desc: '+20 Armor, +20 Magic Resist',
    apply(u) { u.armor += 20; u.mr += 20; }
  },
  keg: {
    name: 'Powder Keg', icon: '\u{1F6E2}', comp: true,
    desc: '+12% Attack Speed',
    apply(u) { u.as *= 1.12; }
  },
  sextant: {
    name: 'Brass Sextant', icon: '\u{1F4D0}', comp: true,
    desc: '+15 starting Mana',
    apply(u) { u.mana = Math.min(u.maxMana, u.mana + 15); }
  },

  /* ------------- forged ------------- */

  bloodletter: {
    name: 'The Bloodletter', icon: '⚔️', from: ['blade', 'blade'],
    desc: '+45 Attack Damage. Gain 10 Attack Damage whenever this unit lands a killing blow.',
    apply(u, sim) {
      u.ad += 45;
      u.hooks.onKill.push(function (self) { self.ad += 10; });
    }
  },

  reckoning: {
    name: "Corsair's Reckoning", icon: '\u{1F5DD}', from: ['blade', 'lens'],
    desc: '+20 Attack Damage, +20 Ability Power, +25% Omnivamp.',
    apply(u) { u.ad += 20; u.ap += 20; u.omnivamp += 0.25; }
  },

  ironclad: {
    name: 'Ironclad Cutlass', icon: '\u{1F528}', from: ['blade', 'plate'],
    desc: '+15 Attack Damage, +200 Health. At 50% Health, gain a shield equal to 30% max Health and 25% Attack Damage.',
    apply(u, sim) {
      u.ad += 15; addMaxHp(u, 200);
      u.hooks.onDamaged.push(function (self) {
        if (self.ircUsed || self.hp > self.maxHp * 0.5) return;
        self.ircUsed = true;
        self.ad *= 1.25;
        sim.addShield(self, self.maxHp * 0.30, 999);
        sim.fx('pop', self, null, '#ff9d5c');
      });
    }
  },

  rapier: {
    name: 'Rapier of the Reef', icon: '\u{1F3F9}', from: ['blade', 'keg'],
    desc: '+18 Attack Damage. Attacks grant 6% Attack Speed, stacking without limit.',
    apply(u) {
      u.ad += 18;
      u.hooks.onAttack.push(function (self) { self.as *= 1.06; });
    }
  },

  buccEdge: {
    name: "Buccaneer's Edge", icon: '\u{1F3AF}', from: ['blade', 'sextant'],
    desc: '+15 Attack Damage, +15 Mana. Attacks restore 6 bonus Mana.',
    apply(u) {
      u.ad += 15; u.mana = Math.min(u.maxMana, u.mana + 15);
      u.hooks.onAttack.push(function (self) { self.mana = Math.min(self.maxMana, self.mana + 6); });
    }
  },

  abyssalPrism: {
    name: 'Abyssal Prism', icon: '\u{1F48E}', from: ['lens', 'lens'],
    desc: '+80 Ability Power.',
    apply(u) { u.ap += 80; }
  },

  coralAegis: {
    name: 'Coral Aegis', icon: '\u{1F9FF}', from: ['lens', 'plate'],
    desc: '+30 Ability Power, +25 Armor and Magic Resist. Gain a 350 Health shield for the first 10 seconds.',
    apply(u, sim) {
      u.ap += 30; u.armor += 25; u.mr += 25;
      sim.addShield(u, 350, 10);
    }
  },

  stormglass: {
    name: 'Stormglass', icon: '\u{1F300}', from: ['lens', 'keg'],
    desc: '+30 Ability Power, +15% Attack Speed. After casting, gain 40% Attack Speed for 5 seconds.',
    apply(u, sim) {
      u.ap += 30; u.as *= 1.15;
      u.hooks.onCast.push(function (self) { sim.addBuff(self, 'as', 1.40, 5); });
    }
  },

  sirensLocket: {
    name: "Siren's Locket", icon: '\u{1F4FF}', from: ['lens', 'sextant'],
    desc: '+25 Ability Power, +20 Mana. After casting, restore 20 Mana and gain 10 permanent Ability Power.',
    apply(u) {
      u.ap += 25; u.mana = Math.min(u.maxMana, u.mana + 20);
      u.hooks.onCast.push(function (self) {
        self.mana = Math.min(self.maxMana, self.mana + 20); self.ap += 10;
      });
    }
  },

  hullDeep: {
    name: 'Hull of the Deep', icon: '\u{1F6A2}', from: ['plate', 'plate'],
    desc: '+800 Health. Regenerate 3% max Health per second.',
    apply(u) {
      addMaxHp(u, 800);
      u.itemRegen = (u.itemRegen || 0) + 0.03;
    }
  },

  boardingHooks: {
    name: 'Boarding Hooks', icon: '⛓️', from: ['plate', 'keg'],
    desc: '+250 Health, +12% Attack Speed. Each attack made or taken grants 3 Armor and Magic Resist (max 25 stacks).',
    apply(u) {
      addMaxHp(u, 250); u.as *= 1.12;
      u.bhStacks = 0;
      const grow = function (self) {
        if (self.bhStacks >= 25) return;
        self.bhStacks++; self.armor += 3; self.mr += 3;
      };
      u.hooks.onAttack.push(grow);
      u.hooks.onDamaged.push(grow);
    }
  },

  drownedAnchor: {
    name: 'Drowned Anchor', icon: '⚓', from: ['plate', 'sextant'],
    desc: '+300 Health, +20 Mana. After casting, shield this unit and the 2 lowest-Health allies for 300 for 6 seconds.',
    apply(u, sim) {
      addMaxHp(u, 300); u.mana = Math.min(u.maxMana, u.mana + 20);
      u.hooks.onCast.push(function (self) {
        const mates = sim.livingAllies(self.team).filter(a => a !== self)
          .sort((a, b) => a.hp / a.maxHp - b.hp / b.maxHp).slice(0, 2);
        [self].concat(mates).forEach(t => { sim.addShield(t, 300, 6); sim.fx('pop', t, null, '#7fe3ff'); });
      });
    }
  },

  grapeshot: {
    name: 'Grapeshot Bandolier', icon: '\u{1F4A5}', from: ['keg', 'keg'],
    desc: '+45% Attack Speed. Attacks burn the target for 1.5% max Health per second and reduce its healing by 33% for 5s.',
    apply(u, sim) {
      u.as *= 1.45;
      u.hooks.onAttack.push(function (self, tgt) {
        if (tgt && tgt.alive) sim.applyBurn(tgt, 0.015, 5, self);
      });
    }
  },

  windrunner: {
    name: "Windrunner's Chart", icon: '\u{1F5FA}', from: ['keg', 'sextant'],
    desc: '+15% Attack Speed, +15 Mana. Every third attack chains lightning to 3 enemies for 90 magic damage and shreds 30% Magic Resist for 5s.',
    apply(u, sim) {
      u.as *= 1.15; u.mana = Math.min(u.maxMana, u.mana + 15);
      u.wrCount = 0;
      u.hooks.onAttack.push(function (self, tgt) {
        self.wrCount++;
        if (self.wrCount % 3 !== 0) return;
        const foes = sim.livingEnemies(self.team)
          .sort((a, b) => sim.dist(self, a) - sim.dist(self, b)).slice(0, 3);
        for (const f of foes) {
          sim.fx('tracer', f, self, '#8fd4ff');
          sim.damage(self, f, 90, 'magic');
          sim.applyShredMr(f, 0.30, 5);
        }
      });
    }
  },

  krakenCompass: {
    name: "Kraken's Compass", icon: '\u{1F9ED}', from: ['sextant', 'sextant'],
    desc: '+15 Ability Power, +30 Mana. After casting, restore 30 Mana.',
    apply(u) {
      u.ap += 15; u.mana = Math.min(u.maxMana, u.mana + 30);
      u.hooks.onCast.push(function (self) { self.mana = Math.min(self.maxMana, self.mana + 30); });
    }
  }
};

for (const k in ITEMS) ITEMS[k].id = k;

/* recipe lookup: "blade+lens" -> item id */
const RECIPES = {};
for (const k in ITEMS) {
  const it = ITEMS[k];
  if (!it.from) continue;
  RECIPES[it.from.slice().sort().join('+')] = k;
}

function combineItems(a, b) {
  return RECIPES[[a, b].sort().join('+')] || null;
}
function isComponent(id) { return !!(ITEMS[id] && ITEMS[id].comp); }
function forgedList() { return Object.keys(ITEMS).filter(k => !ITEMS[k].comp); }
