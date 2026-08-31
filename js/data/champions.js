/* ============================================================
   CHAMPIONS - 44 units across 5 tiers.
   Star scaling: Health x1.8 per star, Attack Damage x1.55 per star,
   ability values are listed explicitly per star.
   cast(sim, self, V) is called when the unit reaches full mana.
   ============================================================ */
'use strict';

const SV = (arr, s) => arr[s.star - 1];

const CHAMPIONS = [

  /* =============== TIER 1 =============== */
  {
    id: 'barnaby', name: 'Barnaby Kegg', icon: '\u{1F37A}', cost: 1, traits: ['bosun', 'corsair'],
    hp: 700, ad: 50, as: 0.6, armor: 45, mr: 45, range: 1, mana: [30, 70],
    ab: {
      name: 'Keg Slam',
      desc: 'Slam a powder keg into the deck, dealing {dmg} magic damage to nearby enemies and gaining a {shield} Health shield.',
      vals: { dmg: [160, 240, 400], shield: [180, 300, 550] },
      cast(sim, s, V) {
        sim.fx('shock', s, null, '#ffb44d');
        sim.addShield(s, SV(V.shield, s) * sim.ap(s), 8);
        for (const e of sim.enemiesNear(s, 2)) sim.damage(s, e, SV(V.dmg, s) * sim.ap(s), 'magic');
      }
    }
  },
  {
    id: 'pip', name: 'Pip Sparrow', icon: '\u{1F426}', cost: 1, traits: ['swash', 'corsair'],
    hp: 550, ad: 55, as: 0.75, armor: 25, mr: 25, range: 1, mana: [20, 50],
    ab: {
      name: 'Featherstep',
      desc: 'Skip to the lowest-Health enemy and strike for {dmg}% Attack Damage, then gain {as}% Attack Speed for 5 seconds.',
      vals: { dmg: [190, 240, 330], as: [40, 55, 90] },
      cast(sim, s, V) {
        const t = sim.lowestEnemy(s.team) || sim.pickTarget(s); if (!t) return;
        sim.blinkNear(s, t);
        sim.fx('slash', t, s, '#9ef0c0');
        sim.damage(s, t, s.ad * SV(V.dmg, s) / 100, 'physical');
        sim.addBuff(s, 'as', 1 + SV(V.as, s) / 100, 5);
      }
    }
  },
  {
    id: 'saltyjo', name: 'Salty Jo', icon: '\u{1F52B}', cost: 1, traits: ['gunner', 'corsair'],
    hp: 500, ad: 48, as: 0.7, armor: 20, mr: 20, range: 4, mana: [20, 55],
    ab: {
      name: 'Three Barrels',
      desc: 'Fire three shots at the current target for {dmg}% Attack Damage each.',
      vals: { dmg: [85, 105, 145] },
      cast(sim, s, V) {
        const t = sim.pickTarget(s); if (!t) return;
        for (let i = 0; i < 3; i++) {
          sim.delay(i * 0.12, () => {
            if (!t.alive || !s.alive) return;
            sim.fx('tracer', t, s, '#ffd27a');
            sim.damage(s, t, s.ad * SV(V.dmg, s) / 100, 'physical');
          });
        }
      }
    }
  },
  {
    id: 'nerida', name: 'Nerida', icon: '\u{1F9DC}', cost: 1, traits: ['siren', 'tidecaller'],
    hp: 520, ad: 38, as: 0.65, armor: 20, mr: 25, range: 3, mana: [30, 65],
    ab: {
      name: 'Salt Balm',
      desc: 'Heal the lowest-Health ally for {heal} and shield them for {shield} for 6 seconds.',
      vals: { heal: [220, 340, 600], shield: [120, 190, 340] },
      cast(sim, s, V) {
        const a = sim.lowestAlly(s.team) || s;
        sim.heal(s, a, SV(V.heal, s) * sim.ap(s));
        sim.addShield(a, SV(V.shield, s) * sim.ap(s), 6);
        sim.fx('pop', a, null, '#7fe3ff');
      }
    }
  },
  {
    id: 'grimscale', name: 'Grimscale', icon: '\u{1F41F}', cost: 1, traits: ['harpooner', 'ghost'],
    hp: 620, ad: 52, as: 0.65, armor: 35, mr: 30, range: 1, mana: [40, 80],
    ab: {
      name: 'Gaff Hook',
      desc: 'Drag the farthest enemy to your side, dealing {dmg} magic damage and stunning them for {stun}s.',
      vals: { dmg: [140, 210, 340], stun: [1, 1.25, 2] },
      cast(sim, s, V) {
        const t = sim.farthestEnemy(s); if (!t) return;
        sim.fx('chain', t, s, '#b6ffce');
        sim.pullTo(s, t);
        sim.damage(s, t, SV(V.dmg, s) * sim.ap(s), 'magic');
        sim.stun(t, SV(V.stun, s));
      }
    }
  },
  {
    id: 'tuck', name: "Cap'n Tuck", icon: '\u{1F9ED}', cost: 1, traits: ['navigator', 'navy'],
    hp: 560, ad: 42, as: 0.7, armor: 30, mr: 30, range: 3, mana: [25, 60],
    ab: {
      name: 'Chart the Course',
      desc: 'Grant all allies {mana} Mana and {as}% Attack Speed for 6 seconds.',
      vals: { mana: [12, 18, 30], as: [22, 32, 55] },
      cast(sim, s, V) {
        for (const a of sim.livingAllies(s.team)) {
          a.mana = Math.min(a.maxMana, a.mana + SV(V.mana, s));
          sim.addBuff(a, 'as', 1 + SV(V.as, s) / 100, 6);
          sim.fx('pop', a, null, '#ffe9a8');
        }
      }
    }
  },
  {
    id: 'brine', name: 'Brine Wraith', icon: '\u{1F47B}', cost: 1, traits: ['ghost', 'reaver'],
    hp: 600, ad: 54, as: 0.65, armor: 30, mr: 30, range: 1, mana: [30, 60],
    ab: {
      name: 'Drown the Living',
      desc: 'Deal {dmg} magic damage to the target and heal for {heal}% of the damage dealt.',
      vals: { dmg: [200, 300, 520], heal: [60, 70, 90] },
      cast(sim, s, V) {
        const t = sim.pickTarget(s); if (!t) return;
        sim.fx('drain', t, s, '#a98bff');
        const dealt = sim.damage(s, t, SV(V.dmg, s) * sim.ap(s), 'magic');
        sim.heal(s, s, dealt * SV(V.heal, s) / 100);
      }
    }
  },
  {
    id: 'marlowe', name: 'Marlowe', icon: '⚓', cost: 1, traits: ['gunner', 'navy'],
    hp: 540, ad: 50, as: 0.65, armor: 30, mr: 30, range: 4, mana: [30, 60],
    ab: {
      name: 'Hull-Piercer',
      desc: 'Fire a shot for {dmg}% Attack Damage that ignores {pen}% of the target Armor.',
      vals: { dmg: [180, 230, 320], pen: [50, 60, 85] },
      cast(sim, s, V) {
        const t = sim.pickTarget(s); if (!t) return;
        sim.fx('tracer', t, s, '#cfe6ff');
        sim.damage(s, t, s.ad * SV(V.dmg, s) / 100, 'physical', { pen: SV(V.pen, s) / 100 });
      }
    }
  },
  {
    id: 'squall', name: 'Squall', icon: '⚡', cost: 1, traits: ['stormborn', 'navigator'],
    hp: 520, ad: 40, as: 0.7, armor: 20, mr: 25, range: 3, mana: [25, 60],
    ab: {
      name: 'Forked Sky',
      desc: 'Lightning arcs to {n} enemies, dealing {dmg} magic damage to each.',
      vals: { dmg: [140, 210, 380], n: [3, 3, 4] },
      cast(sim, s, V) {
        const foes = sim.nearestEnemies(s, SV(V.n, s));
        for (const f of foes) { sim.fx('bolt', f, s, '#8fd4ff'); sim.damage(s, f, SV(V.dmg, s) * sim.ap(s), 'magic'); }
      }
    }
  },
  {
    id: 'ned', name: 'Old Anchor Ned', icon: '\u{1F9BE}', cost: 1, traits: ['bosun', 'navy'],
    hp: 750, ad: 45, as: 0.55, armor: 55, mr: 55, range: 1, mana: [40, 80],
    ab: {
      name: 'Anchor Down',
      desc: 'Gain a {shield} Health shield and {res} Armor and Magic Resist for 8 seconds.',
      vals: { shield: [250, 400, 750], res: [30, 45, 80] },
      cast(sim, s, V) {
        sim.addShield(s, SV(V.shield, s) * sim.ap(s), 8);
        sim.addFlat(s, 'armor', SV(V.res, s), 8);
        sim.addFlat(s, 'mr', SV(V.res, s), 8);
        sim.fx('pop', s, null, '#9fb8d8');
      }
    }
  },
  {
    id: 'coral', name: 'Coral', icon: '\u{1F41A}', cost: 1, traits: ['tidecaller', 'siren'],
    hp: 540, ad: 40, as: 0.65, armor: 25, mr: 25, range: 3, mana: [40, 80],
    ab: {
      name: 'Reef Bloom',
      desc: 'Burst coral at the target for {dmg} magic damage to it and adjacent enemies, healing nearby allies for {heal}.',
      vals: { dmg: [150, 225, 380], heal: [130, 200, 350] },
      cast(sim, s, V) {
        const t = sim.pickTarget(s); if (!t) return;
        sim.fx('shock', t, null, '#79ffd0');
        sim.damage(s, t, SV(V.dmg, s) * sim.ap(s), 'magic');
        for (const e of sim.enemiesNear(t, 1, s.team)) sim.damage(s, e, SV(V.dmg, s) * sim.ap(s), 'magic');
        for (const a of sim.alliesNear(s, 2)) sim.heal(s, a, SV(V.heal, s) * sim.ap(s));
      }
    }
  },
  {
    id: 'finn', name: 'Fishgut Finn', icon: '\u{1FA9D}', cost: 1, traits: ['harpooner', 'corsair'],
    hp: 600, ad: 55, as: 0.7, armor: 30, mr: 25, range: 1, mana: [20, 50],
    ab: {
      name: 'Gut Hook',
      desc: 'Rip the target for {dmg}% Attack Damage as physical damage plus {tr} true damage.',
      vals: { dmg: [160, 200, 280], tr: [60, 95, 170] },
      cast(sim, s, V) {
        const t = sim.pickTarget(s); if (!t) return;
        sim.fx('slash', t, s, '#ff9d9d');
        sim.damage(s, t, s.ad * SV(V.dmg, s) / 100, 'physical');
        sim.damage(s, t, SV(V.tr, s) * sim.ap(s), 'true');
        sim.applyShred(t, 0.25, 5);
      }
    }
  },

  /* =============== TIER 2 =============== */
  {
    id: 'isla', name: 'Isla Redmane', icon: '\u{1F5E1}', cost: 2, traits: ['swash', 'corsair'],
    hp: 620, ad: 58, as: 0.8, armor: 30, mr: 30, range: 1, mana: [10, 40],
    ab: {
      name: 'Crimson Flurry',
      desc: 'Strike four times for {dmg}% Attack Damage each. These strikes can critically strike.',
      vals: { dmg: [60, 75, 115] },
      cast(sim, s, V) {
        for (let i = 0; i < 4; i++) sim.delay(i * 0.13, () => {
          const t = sim.pickTarget(s); if (!t || !s.alive) return;
          sim.fx('slash', t, s, '#ff6b6b');
          sim.damage(s, t, s.ad * SV(V.dmg, s) / 100, 'physical', { canCrit: true });
        });
      }
    }
  },
  {
    id: 'doss', name: 'Deadeye Doss', icon: '\u{1F3AF}', cost: 2, traits: ['gunner', 'reaver'],
    hp: 560, ad: 62, as: 0.65, armor: 25, mr: 25, range: 4, mana: [40, 80],
    ab: {
      name: "Widow's Round",
      desc: 'Fire a slug at the lowest-Health enemy for {dmg}% Attack Damage, increased by up to {amp}% based on how wounded they are.',
      vals: { dmg: [230, 290, 420], amp: [80, 100, 160] },
      cast(sim, s, V) {
        const t = sim.lowestEnemy(s.team); if (!t) return;
        const missing = 1 - t.hp / t.maxHp;
        sim.fx('tracer', t, s, '#ff5f5f');
        sim.damage(s, t, s.ad * SV(V.dmg, s) / 100 * (1 + missing * SV(V.amp, s) / 100), 'physical', { canCrit: true });
      }
    }
  },
  {
    id: 'morgause', name: 'Morgause', icon: '\u{1F3B6}', cost: 2, traits: ['siren', 'stormborn'],
    hp: 580, ad: 40, as: 0.6, armor: 25, mr: 30, range: 3, mana: [40, 90],
    ab: {
      name: 'Dirge of the Drowned',
      desc: 'Sing at the densest cluster of enemies, dealing {dmg} magic damage in a wide area.',
      vals: { dmg: [280, 420, 780] },
      cast(sim, s, V) {
        const c = sim.bestCluster(s.team, 1);
        if (!c) return;
        sim.fx('nova', c, null, '#c58bff');
        for (const e of c.list) sim.damage(s, e, SV(V.dmg, s) * sim.ap(s), 'magic');
      }
    }
  },
  {
    id: 'kelpar', name: 'Kelpar', icon: '\u{1F40B}', cost: 2, traits: ['leviathan', 'tidecaller'],
    hp: 800, ad: 50, as: 0.55, armor: 45, mr: 45, range: 1, mana: [50, 100],
    ab: {
      name: 'Whalesong',
      desc: 'Heal all allies for {heal} and deal {dmg} magic damage to adjacent enemies.',
      vals: { heal: [180, 270, 480], dmg: [140, 210, 380] },
      cast(sim, s, V) {
        for (const a of sim.livingAllies(s.team)) { sim.heal(s, a, SV(V.heal, s) * sim.ap(s)); sim.fx('pop', a, null, '#7fe3ff'); }
        for (const e of sim.enemiesNear(s, 1)) sim.damage(s, e, SV(V.dmg, s) * sim.ap(s), 'magic');
      }
    }
  },
  {
    id: 'bess', name: 'Bilgewater Bess', icon: '\u{1F4AA}', cost: 2, traits: ['bosun', 'harpooner'],
    hp: 820, ad: 55, as: 0.6, armor: 45, mr: 40, range: 1, mana: [40, 90],
    ab: {
      name: 'Hook and Slam',
      desc: 'Yank the two nearest enemies in, dealing {dmg} magic damage and stunning them for {stun}s.',
      vals: { dmg: [200, 300, 540], stun: [1.25, 1.5, 2.5] },
      cast(sim, s, V) {
        const foes = sim.nearestEnemies(s, 2);
        for (const t of foes) {
          sim.fx('chain', t, s, '#ffcf8f');
          sim.pullTo(s, t);
          sim.damage(s, t, SV(V.dmg, s) * sim.ap(s), 'magic');
          sim.stun(t, SV(V.stun, s));
        }
      }
    }
  },
  {
    id: 'voss', name: 'Quartermaster Voss', icon: '\u{1F4E6}', cost: 2, traits: ['navigator', 'navy'],
    hp: 700, ad: 45, as: 0.6, armor: 40, mr: 40, range: 3, mana: [30, 70],
    ab: {
      name: 'Resupply',
      desc: 'Shield the three lowest-Health allies for {shield} for 8 seconds and grant them {mana} Mana.',
      vals: { shield: [260, 390, 700], mana: [15, 22, 40] },
      cast(sim, s, V) {
        const allies = sim.livingAllies(s.team).sort((a, b) => a.hp / a.maxHp - b.hp / b.maxHp).slice(0, 3);
        for (const a of allies) {
          sim.addShield(a, SV(V.shield, s) * sim.ap(s), 8);
          a.mana = Math.min(a.maxMana, a.mana + SV(V.mana, s));
          sim.fx('pop', a, null, '#ffe9a8');
        }
      }
    }
  },
  {
    id: 'silas', name: 'Drowned Silas', icon: '\u{1F480}', cost: 2, traits: ['ghost', 'bosun'],
    hp: 850, ad: 52, as: 0.6, armor: 50, mr: 45, range: 1, mana: [40, 80],
    ab: {
      name: 'Barnacle Skin',
      desc: 'Gain a {shield} Health shield, then deal {dmg} magic damage to nearby enemies each second for 3 seconds.',
      vals: { shield: [300, 450, 820], dmg: [70, 105, 190] },
      cast(sim, s, V) {
        sim.addShield(s, SV(V.shield, s) * sim.ap(s), 8);
        for (let i = 0; i < 3; i++) sim.delay(i, () => {
          if (!s.alive) return;
          sim.fx('shock', s, null, '#87f5b5');
          for (const e of sim.enemiesNear(s, 1)) sim.damage(s, e, SV(V.dmg, s) * sim.ap(s), 'magic');
        });
      }
    }
  },
  {
    id: 'mira', name: 'Tempest Mira', icon: '\u{1F329}', cost: 2, traits: ['stormborn', 'siren'],
    hp: 570, ad: 42, as: 0.65, armor: 25, mr: 30, range: 4, mana: [30, 70],
    ab: {
      name: 'Thunderhead',
      desc: 'Call down a bolt for {dmg} magic damage to the target and half that to enemies beside it, shredding {shred}% Magic Resist for 6s.',
      vals: { dmg: [260, 390, 700], shred: [25, 30, 45] },
      cast(sim, s, V) {
        const t = sim.pickTarget(s); if (!t) return;
        sim.fx('bolt', t, s, '#8fd4ff');
        sim.damage(s, t, SV(V.dmg, s) * sim.ap(s), 'magic');
        sim.applyShredMr(t, SV(V.shred, s) / 100, 6);
        for (const e of sim.enemiesNear(t, 1, s.team)) {
          sim.damage(s, e, SV(V.dmg, s) * 0.5 * sim.ap(s), 'magic');
          sim.applyShredMr(e, SV(V.shred, s) / 100, 6);
        }
      }
    }
  },
  {
    id: 'hookjaw', name: 'Hookjaw', icon: '\u{1F988}', cost: 2, traits: ['harpooner', 'reaver'],
    hp: 700, ad: 60, as: 0.7, armor: 35, mr: 30, range: 1, mana: [20, 60],
    ab: {
      name: 'Feeding Frenzy',
      desc: 'Leap at the lowest-Health enemy and bite for {dmg}% Attack Damage, healing for {heal} Health.',
      vals: { dmg: [200, 250, 360], heal: [180, 270, 480] },
      cast(sim, s, V) {
        const t = sim.lowestEnemy(s.team); if (!t) return;
        sim.blinkNear(s, t);
        sim.fx('slash', t, s, '#ff8f5c');
        sim.damage(s, t, s.ad * SV(V.dmg, s) / 100, 'physical', { canCrit: true });
        sim.heal(s, s, SV(V.heal, s) * sim.ap(s));
      }
    }
  },
  {
    id: 'halloway', name: 'Gunny Halloway', icon: '\u{1F4A3}', cost: 2, traits: ['gunner', 'navigator'],
    hp: 580, ad: 55, as: 0.75, armor: 25, mr: 25, range: 4, mana: [20, 55],
    ab: {
      name: 'Grapeshot',
      desc: 'Spray the three nearest enemies with pellets, hitting each for {dmg}% Attack Damage twice.',
      vals: { dmg: [70, 90, 130] },
      cast(sim, s, V) {
        const foes = sim.nearestEnemies(s, 3);
        for (let i = 0; i < 2; i++) sim.delay(i * 0.15, () => {
          for (const f of foes) {
            if (!f.alive || !s.alive) continue;
            sim.fx('tracer', f, s, '#ffd27a');
            sim.damage(s, f, s.ad * SV(V.dmg, s) / 100, 'physical');
          }
        });
      }
    }
  },
  {
    id: 'selka', name: 'Selka', icon: '\u{1F42C}', cost: 2, traits: ['tidecaller', 'swash'],
    hp: 640, ad: 54, as: 0.8, armor: 30, mr: 35, range: 1, mana: [15, 45],
    ab: {
      name: 'Dance of Tides',
      desc: 'Strike three times for {dmg}% Attack Damage, healing the lowest-Health ally for {heal} with each strike.',
      vals: { dmg: [70, 88, 125], heal: [80, 120, 210] },
      cast(sim, s, V) {
        for (let i = 0; i < 3; i++) sim.delay(i * 0.14, () => {
          const t = sim.pickTarget(s); if (!t || !s.alive) return;
          sim.fx('slash', t, s, '#7fe3ff');
          sim.damage(s, t, s.ad * SV(V.dmg, s) / 100, 'physical');
          const a = sim.lowestAlly(s.team) || s;
          sim.heal(s, a, SV(V.heal, s) * sim.ap(s));
        });
      }
    }
  },

  /* =============== TIER 3 =============== */
  {
    id: 'ravenna', name: 'Captain Ravenna', icon: '\u{1F339}', cost: 3, traits: ['corsair', 'swash'],
    hp: 750, ad: 70, as: 0.8, armor: 35, mr: 35, range: 1, mana: [20, 60],
    ab: {
      name: 'Blackrose Flourish',
      desc: 'Unleash five cuts for {dmg}% Attack Damage each, gaining {crit}% Critical Strike Chance for the rest of combat.',
      vals: { dmg: [65, 80, 125], crit: [10, 15, 30] },
      cast(sim, s, V) {
        s.crit += SV(V.crit, s) / 100;
        for (let i = 0; i < 5; i++) sim.delay(i * 0.1, () => {
          const t = sim.pickTarget(s); if (!t || !s.alive) return;
          sim.fx('slash', t, s, '#ff7ba8');
          sim.damage(s, t, s.ad * SV(V.dmg, s) / 100, 'physical', { canCrit: true });
        });
      }
    }
  },
  {
    id: 'dredge', name: 'Dredge', icon: '\u{1F980}', cost: 3, traits: ['leviathan', 'bosun'],
    hp: 950, ad: 65, as: 0.55, armor: 55, mr: 50, range: 1, mana: [50, 110],
    ab: {
      name: 'Crushing Claw',
      desc: 'Crush all enemies within two hexes for {dmg} magic damage, stunning them for {stun}s.',
      vals: { dmg: [260, 390, 720], stun: [1.25, 1.5, 3] },
      cast(sim, s, V) {
        sim.fx('shock', s, null, '#ff9166');
        for (const e of sim.enemiesNear(s, 2)) {
          sim.damage(s, e, SV(V.dmg, s) * sim.ap(s), 'magic');
          sim.stun(e, SV(V.stun, s));
        }
      }
    }
  },
  {
    id: 'corvane', name: 'Admiral Corvane', icon: '\u{1F396}', cost: 3, traits: ['navy', 'gunner'],
    hp: 720, ad: 68, as: 0.7, armor: 35, mr: 35, range: 4, mana: [40, 90],
    ab: {
      name: 'Broadside',
      desc: 'Fire a full broadside at the four nearest enemies for {dmg}% Attack Damage plus {bonus} magic damage.',
      vals: { dmg: [120, 150, 210], bonus: [80, 120, 220] },
      cast(sim, s, V) {
        const foes = sim.nearestEnemies(s, 4);
        foes.forEach((f, i) => sim.delay(i * 0.08, () => {
          if (!f.alive || !s.alive) return;
          sim.fx('tracer', f, s, '#ffd27a');
          sim.damage(s, f, s.ad * SV(V.dmg, s) / 100, 'physical');
          sim.damage(s, f, SV(V.bonus, s) * sim.ap(s), 'magic');
        }));
      }
    }
  },
  {
    id: 'meredine', name: 'Meredine', icon: '\u{1F3BC}', cost: 3, traits: ['siren', 'tidecaller'],
    hp: 700, ad: 45, as: 0.6, armor: 30, mr: 40, range: 3, mana: [40, 100],
    ab: {
      name: 'Hymn of the Deep',
      desc: 'Heal all allies for {heal} and grant them {ap} Ability Power for the rest of combat.',
      vals: { heal: [300, 450, 850], ap: [15, 22, 45] },
      cast(sim, s, V) {
        for (const a of sim.livingAllies(s.team)) {
          sim.heal(s, a, SV(V.heal, s) * sim.ap(s));
          a.ap += SV(V.ap, s);
          sim.fx('pop', a, null, '#b6a2ff');
        }
      }
    }
  },
  {
    id: 'skarn', name: 'Skarn the Hollow', icon: '\u{1F441}', cost: 3, traits: ['ghost', 'harpooner'],
    hp: 820, ad: 66, as: 0.65, armor: 45, mr: 40, range: 1, mana: [40, 85],
    ab: {
      name: 'Soul Drag',
      desc: 'Haul the two farthest enemies to you, dealing {dmg} true damage and reducing their Armor by {shred}% for 8s.',
      vals: { dmg: [160, 240, 440], shred: [30, 40, 60] },
      cast(sim, s, V) {
        const foes = sim.livingEnemies(s.team).sort((a, b) => sim.dist(s, b) - sim.dist(s, a)).slice(0, 2);
        for (const t of foes) {
          sim.fx('chain', t, s, '#c9a2ff');
          sim.pullTo(s, t);
          sim.damage(s, t, SV(V.dmg, s) * sim.ap(s), 'true');
          sim.applyShred(t, SV(V.shred, s) / 100, 8);
        }
      }
    }
  },
  {
    id: 'kade', name: 'Bolt-Eye Kade', icon: '\u{1F441}‍\u{1F5E8}', cost: 3, traits: ['stormborn', 'gunner'],
    hp: 680, ad: 62, as: 0.75, armor: 30, mr: 30, range: 4, mana: [30, 70],
    ab: {
      name: 'Storm Rounds',
      desc: 'Fire three charged rounds that each deal {dmg} magic damage and arc to a second enemy for half.',
      vals: { dmg: [180, 270, 500] },
      cast(sim, s, V) {
        for (let i = 0; i < 3; i++) sim.delay(i * 0.16, () => {
          const t = sim.pickTarget(s); if (!t || !s.alive) return;
          sim.fx('bolt', t, s, '#8fd4ff');
          sim.damage(s, t, SV(V.dmg, s) * sim.ap(s), 'magic');
          const near = sim.enemiesNear(t, 2, s.team)[0];
          if (near) { sim.fx('bolt', near, t, '#8fd4ff'); sim.damage(s, near, SV(V.dmg, s) * 0.5 * sim.ap(s), 'magic'); }
        });
      }
    }
  },
  {
    id: 'grull', name: 'Ironbelly Grull', icon: '\u{1F417}', cost: 3, traits: ['bosun', 'reaver'],
    hp: 980, ad: 68, as: 0.6, armor: 50, mr: 45, range: 1, mana: [40, 85],
    ab: {
      name: 'Gorge',
      desc: 'Heal {heal}% of missing Health and smash nearby enemies for {dmg}% Attack Damage.',
      vals: { heal: [30, 38, 60], dmg: [150, 190, 280] },
      cast(sim, s, V) {
        sim.heal(s, s, (s.maxHp - s.hp) * SV(V.heal, s) / 100);
        sim.fx('shock', s, null, '#ffb87a');
        for (const e of sim.enemiesNear(s, 1)) sim.damage(s, e, s.ad * SV(V.dmg, s) / 100, 'physical');
      }
    }
  },
  {
    id: 'sable', name: 'Wavecutter Sable', icon: '\u{1F30A}', cost: 3, traits: ['navigator', 'swash'],
    hp: 760, ad: 66, as: 0.85, armor: 35, mr: 35, range: 1, mana: [15, 50],
    ab: {
      name: 'Wake Cutter',
      desc: 'Cut through the three nearest enemies, dealing {dmg}% Attack Damage to each and gaining {as}% Attack Speed for 4s.',
      vals: { dmg: [130, 165, 240], as: [30, 40, 70] },
      cast(sim, s, V) {
        const foes = sim.nearestEnemies(s, 3);
        sim.addBuff(s, 'as', 1 + SV(V.as, s) / 100, 4);
        foes.forEach((f, i) => sim.delay(i * 0.1, () => {
          if (!f.alive || !s.alive) return;
          sim.blinkNear(s, f);
          sim.fx('slash', f, s, '#7fe3ff');
          sim.damage(s, f, s.ad * SV(V.dmg, s) / 100, 'physical', { canCrit: true });
        }));
      }
    }
  },
  {
    id: 'thalassa', name: 'Thalassa', icon: '\u{1F300}', cost: 3, traits: ['tidecaller', 'stormborn'],
    hp: 700, ad: 48, as: 0.6, armor: 30, mr: 40, range: 4, mana: [40, 95],
    ab: {
      name: 'Tidal Surge',
      desc: 'Send a wave through the enemy line, dealing {dmg} magic damage to the target and everything behind it, and healing allies for {heal}.',
      vals: { dmg: [270, 400, 760], heal: [140, 210, 380] },
      cast(sim, s, V) {
        const t = sim.pickTarget(s); if (!t) return;
        const line = sim.lineTargets(s, t, 5);
        sim.fx('wave', t, s, '#5fd8ff');
        for (const e of line) sim.damage(s, e, SV(V.dmg, s) * sim.ap(s), 'magic');
        for (const a of sim.livingAllies(s.team)) sim.heal(s, a, SV(V.heal, s) * sim.ap(s));
      }
    }
  },

  /* =============== TIER 4 =============== */
  {
    id: 'rook', name: 'Blackwater Rook', icon: '\u{1F5E1}', cost: 4, traits: ['corsair', 'reaver'],
    hp: 850, ad: 85, as: 0.85, armor: 40, mr: 40, range: 1, mana: [20, 55],
    ab: {
      name: 'Cutthroat',
      desc: 'Vanish and reappear beside the lowest-Health enemy, dealing {dmg}% Attack Damage. If this kills them, immediately do it again.',
      vals: { dmg: [280, 340, 600] },
      cast(sim, s, V) {
        const strike = (depth) => {
          const t = sim.lowestEnemy(s.team);
          if (!t || !s.alive || depth > 3) return;
          sim.blinkNear(s, t);
          sim.fx('slash', t, s, '#ff5f8f');
          sim.damage(s, t, s.ad * SV(V.dmg, s) / 100, 'physical', { canCrit: true });
          if (!t.alive) sim.delay(0.25, () => strike(depth + 1));
        };
        strike(0);
      }
    }
  },
  {
    id: 'sirene', name: 'Queen Sirene', icon: '\u{1F451}', cost: 4, traits: ['siren', 'navy'],
    hp: 800, ad: 50, as: 0.6, armor: 40, mr: 50, range: 3, mana: [40, 100],
    ab: {
      name: "Sovereign's Song",
      desc: 'Enthrall the three nearest enemies, stunning them for {stun}s and dealing {dmg} magic damage over the duration.',
      vals: { stun: [1.5, 1.75, 4], dmg: [350, 520, 1100] },
      cast(sim, s, V) {
        const foes = sim.nearestEnemies(s, 3);
        for (const f of foes) {
          sim.stun(f, SV(V.stun, s));
          sim.fx('nova', f, null, '#e59bff');
          for (let i = 0; i < 3; i++) sim.delay(i * 0.4, () => sim.damage(s, f, SV(V.dmg, s) / 3 * sim.ap(s), 'magic'));
        }
      }
    }
  },
  {
    id: 'maelstrom', name: 'Maelstrom', icon: '\u{1F32A}', cost: 4, traits: ['leviathan', 'stormborn'],
    hp: 1100, ad: 70, as: 0.6, armor: 55, mr: 55, range: 2, mana: [60, 130],
    ab: {
      name: 'Whirlpool',
      desc: 'Open a vortex that drags all enemies within three hexes inward and deals {dmg} magic damage over 3 seconds.',
      vals: { dmg: [450, 675, 1500] },
      cast(sim, s, V) {
        const foes = sim.enemiesNear(s, 3);
        for (const f of foes) { sim.pullTo(s, f); sim.fx('nova', f, null, '#6ea8ff'); }
        for (let i = 0; i < 3; i++) sim.delay(i * 0.9, () => {
          for (const f of sim.enemiesNear(s, 3)) sim.damage(s, f, SV(V.dmg, s) / 3 * sim.ap(s), 'magic');
        });
      }
    }
  },
  {
    id: 'vance', name: 'Grand Admiral Vance', icon: '\u{1F396}', cost: 4, traits: ['navy', 'navigator'],
    hp: 900, ad: 70, as: 0.7, armor: 50, mr: 50, range: 3, mana: [40, 90],
    ab: {
      name: 'All Hands',
      desc: 'Shield every ally for {shield} and grant them {as}% Attack Speed for 6s, then bombard the densest cluster for {dmg} magic damage.',
      vals: { shield: [250, 375, 700], as: [25, 35, 65], dmg: [300, 450, 900] },
      cast(sim, s, V) {
        for (const a of sim.livingAllies(s.team)) {
          sim.addShield(a, SV(V.shield, s) * sim.ap(s), 6);
          sim.addBuff(a, 'as', 1 + SV(V.as, s) / 100, 6);
          sim.fx('pop', a, null, '#ffe9a8');
        }
        const c = sim.bestCluster(s.team, 1);
        if (c) { sim.fx('nova', c, null, '#ffb44d'); for (const e of c.list) sim.damage(s, e, SV(V.dmg, s) * sim.ap(s), 'magic'); }
      }
    }
  },
  {
    id: 'barnacleking', name: 'The Barnacle King', icon: '\u{1F41A}', cost: 4, traits: ['ghost', 'bosun'],
    hp: 1200, ad: 65, as: 0.55, armor: 65, mr: 60, range: 1, mana: [70, 140],
    ab: {
      name: 'Rise, Drowned Ones',
      desc: 'Raise your most valuable fallen ally at {rev}% Health, heal yourself for {heal}, and crush nearby enemies for {dmg} magic damage.',
      vals: { rev: [40, 55, 100], heal: [350, 525, 1000], dmg: [200, 300, 600] },
      cast(sim, s, V) {
        sim.heal(s, s, SV(V.heal, s) * sim.ap(s));
        sim.reviveBest(s.team, SV(V.rev, s) / 100);
        sim.fx('shock', s, null, '#a2ffd0');
        for (const e of sim.enemiesNear(s, 2)) sim.damage(s, e, SV(V.dmg, s) * sim.ap(s), 'magic');
      }
    }
  },
  {
    id: 'lyra', name: 'Longshot Lyra', icon: '\u{1F3F9}', cost: 4, traits: ['gunner', 'corsair'],
    hp: 750, ad: 80, as: 0.75, armor: 30, mr: 30, range: 5, mana: [30, 75],
    ab: {
      name: 'Piercing Shot',
      desc: 'Fire a shot that pierces the whole enemy line for {dmg}% Attack Damage, ignoring {pen}% Armor.',
      vals: { dmg: [230, 285, 460], pen: [40, 50, 80] },
      cast(sim, s, V) {
        const t = sim.pickTarget(s); if (!t) return;
        const line = sim.lineTargets(s, t, 6);
        sim.fx('beam', t, s, '#ffe07a');
        for (const e of line) sim.damage(s, e, s.ad * SV(V.dmg, s) / 100, 'physical', { canCrit: true, pen: SV(V.pen, s) / 100 });
      }
    }
  },
  {
    id: 'kessa', name: 'Bloodtide Kessa', icon: '\u{1FA78}', cost: 4, traits: ['reaver', 'swash'],
    hp: 900, ad: 88, as: 0.9, armor: 40, mr: 40, range: 1, mana: [10, 40],
    ab: {
      name: 'Bloodtide',
      desc: 'Enter a frenzy: strike six times for {dmg}% Attack Damage, healing for {ov}% of all damage dealt.',
      vals: { dmg: [55, 68, 110], ov: [35, 45, 80] },
      cast(sim, s, V) {
        sim.addTempOmni(s, SV(V.ov, s) / 100, 2.2);
        for (let i = 0; i < 6; i++) sim.delay(i * 0.11, () => {
          const t = sim.pickTarget(s); if (!t || !s.alive) return;
          sim.fx('slash', t, s, '#ff4d6d');
          sim.damage(s, t, s.ad * SV(V.dmg, s) / 100, 'physical', { canCrit: true });
        });
      }
    }
  },

  /* =============== TIER 5 =============== */
  {
    id: 'kraken', name: 'The Kraken', icon: '\u{1F419}', cost: 5, traits: ['leviathan', 'harpooner'],
    hp: 1400, ad: 95, as: 0.6, armor: 70, mr: 70, range: 2, mana: [50, 120],
    ab: {
      name: 'Fleetbreaker',
      desc: 'Eight tentacles erupt. Drag every enemy within four hexes inward, dealing {dmg} magic damage and stunning them for {stun}s. Enemies below {ex}% Health are devoured outright.',
      vals: { dmg: [500, 750, 4000], stun: [1.5, 2, 5], ex: [12, 15, 40] },
      cast(sim, s, V) {
        const foes = sim.enemiesNear(s, 4);
        sim.fx('nova', s, null, '#7a5fff');
        for (const f of foes) {
          sim.pullTo(s, f);
          sim.fx('chain', f, s, '#9d7bff');
          sim.damage(s, f, SV(V.dmg, s) * sim.ap(s), 'magic');
          sim.stun(f, SV(V.stun, s));
          if (f.alive && f.hp / f.maxHp <= SV(V.ex, s) / 100) sim.execute(s, f);
        }
      }
    }
  },
  {
    id: 'davy', name: 'Davy Grim', icon: '\u{1F480}', cost: 5, traits: ['ghost', 'siren'],
    hp: 1200, ad: 75, as: 0.65, armor: 55, mr: 60, range: 3, mana: [40, 100],
    ab: {
      name: 'The Locker Opens',
      desc: 'Deal {dmg} magic damage to all enemies. Every ally that dies in the next {dur}s returns at {rev}% Health.',
      vals: { dmg: [350, 525, 2000], dur: [6, 8, 30], rev: [40, 50, 100] },
      cast(sim, s, V) {
        for (const e of sim.livingEnemies(s.team)) {
          sim.fx('drain', e, s, '#8f6bff');
          sim.damage(s, e, SV(V.dmg, s) * sim.ap(s), 'magic');
        }
        sim.grantMassRevive(s.team, SV(V.rev, s) / 100, SV(V.dur, s));
      }
    }
  },
  {
    id: 'calypso', name: 'Calypso', icon: '⛈️', cost: 5, traits: ['stormborn', 'tidecaller'],
    hp: 1150, ad: 70, as: 0.65, armor: 50, mr: 60, range: 4, mana: [40, 110],
    ab: {
      name: 'Sovereign Storm',
      desc: 'Summon a hurricane for 4 seconds: strike a random enemy for {dmg} magic damage every 0.4s while healing all allies for {heal} per second.',
      vals: { dmg: [130, 195, 700], heal: [120, 180, 700] },
      cast(sim, s, V) {
        for (let i = 0; i < 10; i++) sim.delay(i * 0.4, () => {
          if (!s.alive) return;
          const foes = sim.livingEnemies(s.team);
          if (foes.length) {
            const t = foes[U.randInt(foes.length)];
            sim.fx('bolt', t, null, '#a8e4ff');
            sim.damage(s, t, SV(V.dmg, s) * sim.ap(s), 'magic');
          }
          if (i % 2 === 0) for (const a of sim.livingAllies(s.team)) sim.heal(s, a, SV(V.heal, s) * 0.8 * sim.ap(s));
        });
      }
    }
  },
  {
    id: 'ashmore', name: 'Blackbeard Ashmore', icon: '\u{1F3F4}', cost: 5, traits: ['corsair', 'gunner', 'reaver'],
    hp: 1100, ad: 100, as: 0.8, armor: 45, mr: 45, range: 3, mana: [30, 70],
    ab: {
      name: 'Six Pistols',
      desc: 'Draw six pistols and fire at the lowest-Health enemies for {dmg}% Attack Damage each. Kills grant {ad} permanent Attack Damage.',
      vals: { dmg: [110, 135, 400], ad: [10, 15, 60] },
      cast(sim, s, V) {
        for (let i = 0; i < 6; i++) sim.delay(i * 0.1, () => {
          if (!s.alive) return;
          const t = sim.lowestEnemy(s.team); if (!t) return;
          sim.fx('tracer', t, s, '#ff9d4d');
          const before = t.alive;
          sim.damage(s, t, s.ad * SV(V.dmg, s) / 100, 'physical', { canCrit: true });
          if (before && !t.alive) s.ad += SV(V.ad, s);
        });
      }
    }
  },
  {
    id: 'nautica', name: 'Empress Nautica', icon: '\u{1F451}', cost: 5, traits: ['navy', 'siren', 'navigator'],
    hp: 1150, ad: 70, as: 0.7, armor: 60, mr: 60, range: 3, mana: [40, 100],
    ab: {
      name: 'Flagship Broadside',
      desc: 'The flagship fires: {dmg} magic damage to all enemies in a huge area. Allies gain {res} Armor and Magic Resist and {ap} Ability Power permanently.',
      vals: { dmg: [400, 600, 2400], res: [25, 35, 120], ap: [20, 30, 120] },
      cast(sim, s, V) {
        const c = sim.bestCluster(s.team, 2);
        if (c) { sim.fx('nova', c, null, '#ffd27a'); for (const e of c.list) sim.damage(s, e, SV(V.dmg, s) * sim.ap(s), 'magic'); }
        for (const a of sim.livingAllies(s.team)) {
          a.armor += SV(V.res, s); a.mr += SV(V.res, s); a.ap += SV(V.ap, s);
          sim.fx('pop', a, null, '#ffe9a8');
        }
      }
    }
  }
];

/* index + pool sizes */
const CHAMP_BY_ID = {};
for (const c of CHAMPIONS) CHAMP_BY_ID[c.id] = c;

const POOL_SIZE = { 1: 29, 2: 22, 3: 18, 4: 12, 5: 10 };
const COST_COLOR = { 1: '#9aa7b4', 2: '#3fbf7f', 3: '#4a9dff', 4: '#c46bff', 5: '#ffb32e' };

/** star-scaled stat block for a champion */
function statsFor(champ, star) {
  const hpMul = Math.pow(1.8, star - 1);
  const adMul = Math.pow(1.55, star - 1);
  return {
    maxHp: Math.round(champ.hp * hpMul),
    ad: Math.round(champ.ad * adMul),
    as: champ.as,
    armor: champ.armor,
    mr: champ.mr,
    range: champ.range,
    manaStart: champ.mana[0],
    maxMana: champ.mana[1]
  };
}
