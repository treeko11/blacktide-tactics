/* ============================================================
   Blacktide Tactics - utilities, hex math, small helpers
   ============================================================ */
'use strict';

const U = {};

/* ---------- random ---------- */
U.rand = () => Math.random();
U.randInt = (n) => Math.floor(Math.random() * n);
U.pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
U.shuffle = (arr) => {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
};
/** weighted pick: table = [[value, weight], ...] */
U.weighted = (table) => {
  let total = 0;
  for (const t of table) total += t[1];
  let r = Math.random() * total;
  for (const t of table) { r -= t[1]; if (r <= 0) return t[0]; }
  return table[table.length - 1][0];
};

U.clamp = (v, lo, hi) => v < lo ? lo : (v > hi ? hi : v);
U.uid = (() => { let n = 1; return () => 'u' + (n++); })();
U.round = (v) => Math.round(v);

/* ---------- board geometry ----------
   Odd-r offset hex layout, pointy-top hexes.
   7 columns x 8 rows. Rows 0-3 = enemy half, rows 4-7 = player half. */
const BOARD = {
  COLS: 7,
  ROWS: 8,
  PLAYER_ROW_MIN: 4,
  HEX_W: 70,          // corner-to-corner width of a pointy-top hex
  HEX_H: 80,          // point-to-point height
  V_SPACE: 60,        // vertical distance between row centers (0.75 * H)
  get WIDTH()  { return this.COLS * this.HEX_W + this.HEX_W / 2 + 8; },
  get HEIGHT() { return (this.ROWS - 1) * this.V_SPACE + this.HEX_H + 8; }
};

/** pixel centre of hex (col,row) */
U.hexPos = (col, row) => ({
  x: col * BOARD.HEX_W + (row % 2 ? BOARD.HEX_W / 2 : 0) + BOARD.HEX_W / 2 + 4,
  y: row * BOARD.V_SPACE + BOARD.HEX_H / 2 + 4
});

/** offset(col,row) -> cube coords */
U.toCube = (col, row) => {
  const x = col - (row - (row & 1)) / 2;
  const z = row;
  return { x, y: -x - z, z };
};

/** hex distance between two offset cells */
U.hexDist = (c1, r1, c2, r2) => {
  const a = U.toCube(c1, r1), b = U.toCube(c2, r2);
  return (Math.abs(a.x - b.x) + Math.abs(a.y - b.y) + Math.abs(a.z - b.z)) / 2;
};

const ODD_R_NEIGHBORS = [
  // even rows                                 odd rows
  [[+1, 0], [0, -1], [-1, -1], [-1, 0], [-1, +1], [0, +1]],
  [[+1, 0], [+1, -1], [0, -1], [-1, 0], [0, +1], [+1, +1]]
];

/** neighbouring cells of (col,row) that are on the board */
U.hexNeighbors = (col, row) => {
  const out = [];
  for (const d of ODD_R_NEIGHBORS[row & 1]) {
    const c = col + d[0], r = row + d[1];
    if (c >= 0 && c < BOARD.COLS && r >= 0 && r < BOARD.ROWS) out.push([c, r]);
  }
  return out;
};

/** all board cells within `range` hexes of (col,row), excluding origin unless inc */
U.hexesInRange = (col, row, range, includeSelf) => {
  const out = [];
  for (let r = 0; r < BOARD.ROWS; r++) {
    for (let c = 0; c < BOARD.COLS; c++) {
      if (!includeSelf && c === col && r === row) continue;
      if (U.hexDist(col, row, c, r) <= range) out.push([c, r]);
    }
  }
  return out;
};

U.cellKey = (c, r) => r * BOARD.COLS + c;

/* ---------- text helpers ---------- */
U.esc = (s) => String(s).replace(/[&<>"]/g, m => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[m]));
U.pct = (v) => Math.round(v * 100) + '%';
U.romanStar = (n) => '★'.repeat(n);

/** replace {x} tokens in ability text with star-scaled arrays */
U.fmtDesc = (desc, vals, star) => {
  return desc.replace(/\{(\w+)\}/g, (m, key) => {
    const v = vals[key];
    if (v === undefined) return m;
    if (Array.isArray(v)) {
      if (star) return '<b>' + v[star - 1] + '</b>';
      return '<b>' + v.join(' / ') + '</b>';
    }
    return '<b>' + v + '</b>';
  });
};

U.el = (tag, cls, html) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html !== undefined) e.innerHTML = html;
  return e;
};
