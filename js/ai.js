/* ============================================================
   AI OPPONENTS - the other seven captains in the lobby.
   Bots draw from the same shared champion pool as the player.
   ============================================================ */
'use strict';

const BOT_NAMES = [
  ['Captain Mordecai', '\u{1F480}'], ['Redsail Yara', '\u{1F3F4}'], ['Old Man Fathom', '\u{1F419}'],
  ['Widow Calder', '\u{1F5E1}'], ['Bosun Krell', '\u{1F4AA}'], ['The Gull', '\u{1F426}'],
  ['Saltbeard Ossy', '\u{1F37A}'], ['Lady Undertow', '\u{1F30A}'], ['Ironhook Vance', '\u{1FA9D}'],
  ['Squid-Eye Pell', '\u{1F991}'], ['Cannonade Rue', '\u{1F52B}'], ['Ghostwake Tam', '\u{1F47B}']
];

const PERSONALITIES = ['econ', 'aggro', 'balanced', 'reroll'];

class Bot {
  constructor(idx, name, icon) {
    this.idx = idx;
    this.name = name;
    this.icon = icon;
    this.isBot = true;
    this.hp = 100;
    this.gold = 2;
    this.level = 1;
    this.xp = 0;
    this.streak = 0;
    this.lastResult = 0;
    this.alive = true;
    this.units = [];              // {champId, star, items[]}
    this.personality = U.pick(PERSONALITIES);
    // pick a comp identity: one origin + one class it will chase
    const origins = Object.keys(TRAITS).filter(k => TRAITS[k].kind === 'origin');
    const classes = Object.keys(TRAITS).filter(k => TRAITS[k].kind === 'class');
    this.comp = [U.pick(origins), U.pick(classes)];
    this.place = 0;
  }

  get targetLevel() {
    const s = Game.stage;
    const table = { 1: 3, 2: 4, 3: 5, 4: 6, 5: 7, 6: 8, 7: 8, 8: 9 };
    let lv = table[Math.min(8, s)] || 9;
    if (this.personality === 'aggro') lv = Math.min(9, lv + 1);
    if (this.personality === 'reroll') lv = Math.max(3, lv - 1);
    return lv;
  }

  /* --------- one economy + shopping turn --------- */
  takeTurn() {
    if (!this.alive) return;

    // income
    let inc = 5 + Math.min(5, Math.floor(this.gold / 10));
    const st = Math.abs(this.streak);
    inc += st >= 5 ? 3 : st >= 4 ? 2 : st >= 2 ? 1 : 0;
    if (this.lastResult > 0) inc += 1;
    inc += Math.max(0, Game.stage - 2);        // bot handicap so they keep pace
    this.gold += inc;
    this.addXp(2);

    // level up
    let guard = 0;
    while (this.level < this.targetLevel && this.gold >= 4 + this.reserve() && guard++ < 20) {
      this.gold -= 4; this.addXp(4);
    }

    // shop
    let rolls = 1;
    if (this.personality === 'reroll' && this.gold > 40) rolls = 4;
    if (this.gold > 55) rolls += 2;
    for (let r = 0; r < rolls; r++) {
      if (r > 0) { if (this.gold < 2 + this.reserve()) break; this.gold -= 2; }
      this.shop();
    }
    this.combine();
    this.maybeItem();
  }

  reserve() {
    if (this.personality === 'econ') return Game.stage < 5 ? 30 : 10;
    if (this.personality === 'balanced') return Game.stage < 4 ? 20 : 0;
    return 0;
  }

  addXp(n) {
    this.xp += n;
    while (this.level < 10 && this.xp >= XP_TABLE[this.level]) {
      this.xp -= XP_TABLE[this.level];
      this.level++;
    }
  }

  score(champId) {
    const c = CHAMP_BY_ID[champId];
    let s = c.cost * 10;
    for (const t of c.traits) if (this.comp.indexOf(t) >= 0) s += 22;
    // already own copies -> chase the upgrade
    const owned = this.units.filter(u => u.champId === champId && u.star === 1).length;
    if (owned === 1) s += 18;
    if (owned === 2) s += 45;
    return s;
  }

  shop() {
    // rollShop already pulls these cards out of the shared pool
    const offers = Game.rollShop(this.level);
    offers.sort((a, b) => this.score(b) - this.score(a));
    const unsold = [];
    for (const id of offers) {
      const c = CHAMP_BY_ID[id];
      const tooPoor = this.gold < c.cost;
      const savingUp = (this.gold - c.cost) < this.reserve() && this.units.length >= this.level;
      const junk = this.score(id) < 25 && this.units.length >= this.level + 3;
      const full = this.units.length >= this.level + 9;
      if (tooPoor || savingUp || junk || full) { unsold.push(id); continue; }
      this.gold -= c.cost;
      this.units.push({ champId: id, star: 1, items: [] });
    }
    Game.returnOffers(unsold);
  }

  combine() {
    for (let star = 1; star <= 2; star++) {
      let again = true;
      while (again) {
        again = false;
        const byId = {};
        for (const u of this.units) {
          if (u.star !== star) continue;
          (byId[u.champId] = byId[u.champId] || []).push(u);
        }
        for (const id in byId) {
          if (byId[id].length >= 3) {
            const three = byId[id].slice(0, 3);
            const items = [];
            for (const u of three) items.push(...u.items);
            this.units = this.units.filter(u => three.indexOf(u) < 0);
            this.units.push({ champId: id, star: star + 1, items: items.slice(0, 3) });
            again = true;
          }
        }
      }
    }
    // trim junk when over bench capacity
    if (this.units.length > this.level + 9) {
      this.units.sort((a, b) => this.power(b) - this.power(a));
      const cut = this.units.splice(this.level + 9);
      for (const u of cut) Game.returnToPool(u.champId, u.star);
    }
  }

  maybeItem() {
    if (Game.round !== 1) return;
    if (Game.stage < 2) return;
    const list = forgedList();
    const best = this.boardUnits().filter(u => u.items.length < 3);
    if (!best.length) return;
    best[0].items.push(U.pick(list));
  }

  power(u) {
    const c = CHAMP_BY_ID[u.champId];
    let p = c.cost * Math.pow(3, u.star - 1) * 10;
    for (const t of c.traits) if (this.comp.indexOf(t) >= 0) p += 8;
    return p;
  }

  boardUnits() {
    return this.units.slice().sort((a, b) => this.power(b) - this.power(a)).slice(0, this.level);
  }

  /** board entries in this bot's own coordinate space (rows 4-7) */
  getBoard() {
    const chosen = this.boardUnits();
    const melee = [], ranged = [];
    for (const u of chosen) (CHAMP_BY_ID[u.champId].range <= 1 ? melee : ranged).push(u);
    const out = [];
    const seats = [];
    // front rows first for melee, back rows for ranged
    for (const row of [4, 5]) for (const col of [3, 2, 4, 1, 5, 0, 6]) seats.push([col, row]);
    const backSeats = [];
    for (const row of [7, 6]) for (const col of [3, 2, 4, 1, 5, 0, 6]) backSeats.push([col, row]);
    let i = 0, j = 0;
    for (const u of melee) {
      const s = seats[i++] || backSeats[j++]; if (!s) break;
      out.push({ champId: u.champId, star: u.star, items: u.items, col: s[0], row: s[1] });
    }
    for (const u of ranged) {
      const s = backSeats[j++] || seats[i++]; if (!s) break;
      out.push({ champId: u.champId, star: u.star, items: u.items, col: s[0], row: s[1] });
    }
    return out;
  }

  traitSummary() {
    const seen = {};
    for (const u of this.boardUnits()) {
      for (const t of CHAMP_BY_ID[u.champId].traits) {
        if (!seen[t]) seen[t] = new Set();
        seen[t].add(u.champId);
      }
    }
    return Object.keys(seen)
      .map(t => ({ id: t, n: seen[t].size, ti: traitTierIdx(TRAITS[t], seen[t].size) }))
      .filter(x => x.ti >= 0)
      .sort((a, b) => b.ti - a.ti || b.n - a.n);
  }
}

function makeBots(n) {
  const names = U.shuffle(BOT_NAMES).slice(0, n);
  return names.map((nm, i) => new Bot(i + 1, nm[0], nm[1]));
}
