/* ============================================================
   UI - board rendering, drag & drop, tooltips, modals
   ============================================================ */
'use strict';

const UI = {
  hexBoard: null, unitLayer: null, fxLayer: null,
  drag: null, hoverUnit: null, combatEls: new Map(),

  init() {
    this.hexBoard = document.getElementById('hexBoard');
    this.unitLayer = document.getElementById('unitLayer');
    this.fxLayer = document.getElementById('fxLayer');
    this.tooltip = document.getElementById('tooltip');
    this.ghost = document.getElementById('dragGhost');
    this.touch = window.matchMedia('(pointer: coarse)').matches;
    if (this.touch) document.body.classList.add('touch');
    // remember where the trait list and cargo hold live on desktop
    const traits = document.getElementById('traitList'), items = document.getElementById('itemBench');
    this.dock = {
      traits: { parent: traits.parentElement, next: traits.nextElementSibling },
      items: { parent: items.parentElement, next: items.nextElementSibling }
    };
    this.buildBoard();
    this.bindGlobal();
    this.syncLayoutMode();
    this.fitLayout();
    window.addEventListener('resize', () => { this.syncLayoutMode(); this.fitLayout(); });
    window.addEventListener('orientationchange', () => setTimeout(() => { this.syncLayoutMode(); this.fitLayout(); }, 250));
  },

  isMobile() { return window.matchMedia('(max-width: 1080px)').matches; },

  /** on narrow screens the traits + cargo hold move into a strip above the bench */
  syncLayoutMode() {
    const mobile = this.isMobile();
    document.body.classList.toggle('mobile', mobile);
    const strips = document.getElementById('mobileStrips');
    const traits = document.getElementById('traitList');
    const items = document.getElementById('itemBench');
    if (mobile) {
      if (traits.parentElement !== strips) strips.appendChild(traits);
      if (items.parentElement !== strips) strips.appendChild(items);
    } else {
      if (traits.parentElement !== this.dock.traits.parent)
        this.dock.traits.parent.insertBefore(traits, this.dock.traits.next);
      if (items.parentElement !== this.dock.items.parent)
        this.dock.items.parent.insertBefore(items, this.dock.items.next);
      document.body.classList.remove('drawer-open');
    }
  },

  /** scale the board and the bottom rows so everything fits the window */
  fitLayout() {
    const bf = document.getElementById('battlefield');
    const wrap = document.getElementById('boardWrap');
    if (bf && wrap) {
      const s = Math.min(1.15,
        (bf.clientWidth - 10) / BOARD.WIDTH,
        (bf.clientHeight - 10) / BOARD.HEIGHT);
      wrap.style.transform = 'translate(-50%,-50%) scale(' + Math.max(0.35, s) + ')';
    }
    const center = document.getElementById('center');
    const mobile = this.isMobile();
    for (const id of ['shopRow', 'benchRow']) {
      const row = document.getElementById(id);
      if (!row) continue;
      row.style.transform = 'none';
      row.style.marginTop = '0';
      if (mobile) continue;           // mobile wraps these rows instead of scaling them
      const natural = row.scrollWidth;
      const avail = center.clientWidth;
      const s = natural > avail ? Math.max(0.5, avail / natural) : 1;
      row.style.transform = 'scale(' + s + ')';
      row.style.marginTop = (s < 1 ? -(row.offsetHeight * (1 - s)) : 0) + 'px';
    }
  },

  /* ---------------- static board ---------------- */
  buildBoard() {
    const wrap = document.getElementById('boardWrap');
    wrap.style.width = BOARD.WIDTH + 'px';
    wrap.style.height = BOARD.HEIGHT + 'px';
    this.hexBoard.innerHTML = '';
    for (let r = 0; r < BOARD.ROWS; r++) {
      for (let c = 0; c < BOARD.COLS; c++) {
        const p = U.hexPos(c, r);
        const h = U.el('div', 'hex ' + (r >= BOARD.PLAYER_ROW_MIN ? 'mine' : 'enemy'));
        h.style.width = BOARD.HEX_W - 3 + 'px';
        h.style.height = BOARD.HEX_H - 3 + 'px';
        h.style.left = (p.x - (BOARD.HEX_W - 3) / 2) + 'px';
        h.style.top = (p.y - (BOARD.HEX_H - 3) / 2) + 'px';
        h.dataset.col = c; h.dataset.row = r;
        h.dataset.drop = r >= BOARD.PLAYER_ROW_MIN ? 'cell' : '';
        this.hexBoard.appendChild(h);
      }
    }
  },

  /* ---------------- full render (planning) ---------------- */
  renderAll() {
    this.renderTop();
    this.renderTraits();
    this.renderItems();
    this.renderPlayers();
    this.renderLog();
    if (Game.phase === 'combat') { this.fitLayout(); return; }   // combat frames drive the board
    this.renderBoardUnits();
    this.renderBench();
    this.renderShop();
    this.fitLayout();
  },

  renderTop() {
    const p = Game.player;
    document.getElementById('stagePill').textContent = Game.stage + '‑' + Game.round;
    const ph = document.getElementById('phasePill');
    const names = { plan: 'PLANNING', combat: 'BATTLE', result: 'AFTERMATH', armory: 'ARMOURY', over: 'FINISHED' };
    ph.textContent = names[Game.phase] || '';
    ph.classList.toggle('combat', Game.phase === 'combat');
    document.getElementById('hpVal').textContent = Math.max(0, p.hp);
    document.getElementById('goldVal').textContent = p.gold;
    const sv = document.getElementById('streakVal');
    const st = p.streak;
    sv.textContent = (st > 0 ? 'W' : st < 0 ? 'L' : '–') + (st ? Math.abs(st) : '');
    document.getElementById('streakStat').classList.toggle('hot', Math.abs(st) >= 3);
    document.getElementById('lvlVal').textContent = p.level;
    const need = XP_TABLE[p.level];
    const pctv = p.level >= 9 ? 100 : Math.min(100, p.xp / need * 100);
    document.getElementById('xpFill').style.width = pctv + '%';
    document.getElementById('xpTxt').textContent = p.level >= 9 ? 'MAX' : p.xp + '/' + need;
    const cap = document.getElementById('capVal');
    cap.textContent = Game.boardCount() + '/' + Game.boardCap();
    cap.parentElement.classList.toggle('over', Game.boardCount() > Game.boardCap());

    const odds = SHOP_ODDS[U.clamp(p.level, 1, 9)];
    document.getElementById('oddsBox').innerHTML = odds.map((o, i) =>
      `<span style="color:${COST_COLOR[i + 1]}">${o}</span>`).join('');

    document.getElementById('readyBtn').disabled = Game.phase !== 'plan';
    document.getElementById('lockBtn').classList.toggle('on', Game.shopLocked);
  },

  renderTraits() {
    const list = Game.traitCounts(Game.player.board);
    const box = document.getElementById('traitList');
    box.innerHTML = '';
    if (!list.length) {
      box.innerHTML = '<div class="panel-empty">Field your crew to muster traits.</div>';
      return;
    }
    for (const t of list) {
      const tr = TRAITS[t.id];
      const cls = traitTierClass(tr, t.ti);
      const row = U.el('div', 'trait-row ' + cls);
      const next = tr.breaks.find(b => b > t.count);
      row.innerHTML =
        `<div class="ti"><span>${tr.icon}</span></div>` +
        `<div class="tn">${tr.name}</div>` +
        `<div class="tc">${t.count}${next ? '<span style="opacity:.5">/' + next + '</span>' : ''}</div>`;
      row.addEventListener('mouseenter', e => this.showTraitTip(e, tr, t));
      row.addEventListener('mouseleave', () => this.hideTip());
      this.addTapInfo(row, e => { this.showTraitTip(e, tr, t); this.pinTip(e); });
      box.appendChild(row);
    }
  },

  renderItems() {
    const box = document.getElementById('itemBench');
    box.innerHTML = '';
    for (const id of Game.player.items) {
      box.appendChild(this.itemEl(id, true));
    }
    if (!Game.player.items.length) {
      box.innerHTML = '<div class="panel-empty">Empty hold.</div>';
    }
  },

  itemEl(id, draggable) {
    const it = ITEMS[id];
    const e = U.el('div', 'item' + (it.comp ? '' : ' forged'), it.icon);
    e.dataset.item = id;
    e.addEventListener('mouseenter', ev => this.showItemTip(ev, id));
    e.addEventListener('mouseleave', () => this.hideTip());
    if (draggable) e.addEventListener('pointerdown', ev => this.beginPointer(ev, { kind: 'item', id }));
    return e;
  },

  renderPlayers() {
    const box = document.getElementById('playerList');
    box.innerHTML = '';
    const list = Game.everyone().slice().sort((a, b) => (b.alive - a.alive) || b.hp - a.hp);
    for (const p of list) {
      const row = U.el('div', 'prow' + (p.isBot ? '' : ' me') + (p.alive ? '' : ' dead') +
        (Game.currentOpponent && Game.currentOpponent.ref === p && Game.phase === 'combat' ? ' foe' : ''));
      row.innerHTML =
        `<div class="hpbg" style="width:${Math.max(0, p.hp)}%"></div>` +
        `<div class="pi">${p.icon}</div><div class="pn">${U.esc(p.name)}</div>` +
        `<div class="plv">${p.level}</div><div class="ph">${Math.max(0, p.hp)}</div>`;
      if (p.isBot) {
        row.addEventListener('mouseenter', e => this.showBotTip(e, p));
        row.addEventListener('mouseleave', () => this.hideTip());
        this.addTapInfo(row, e => { this.showBotTip(e, p); this.pinTip(e); });
      }
      box.appendChild(row);
    }
  },

  renderLog() {
    const box = document.getElementById('log');
    box.innerHTML = Game.logLines.map(l => `<div class="${l.cls}">${l.txt}</div>`).join('');
  },

  /* ---------------- units ---------------- */
  unitEl(u, opts) {
    opts = opts || {};
    const champ = CHAMP_BY_ID[u.champId];
    const el = U.el('div', 'unit t' + champ.cost + ' s' + u.star + (opts.foe ? ' foe' : ''));
    el.innerHTML =
      `<div class="body">${champ.icon}` +
      `<div class="stars">${U.romanStar(u.star)}</div>` +
      `<div class="eqp">${(u.items || []).map(i => `<div class="item mini">${ITEMS[i].icon}</div>`).join('')}</div>` +
      `</div>` +
      `<div class="bars"><div class="bar hp"><i></i><u></u></div>` +
      (opts.mana === false ? '' : `<div class="bar mana"><i></i></div>`) + `</div>`;
    return el;
  },

  renderBoardUnits() {
    this.unitLayer.innerHTML = '';
    this.combatEls.clear();
    for (const u of Game.player.board) {
      const el = this.unitEl(u);
      const p = U.hexPos(u.col, u.row);
      el.style.left = p.x + 'px'; el.style.top = p.y + 'px';
      el.style.pointerEvents = 'auto';
      el.dataset.col = u.col; el.dataset.row = u.row;
      el.querySelector('.bar.hp i').style.transform = 'scaleX(1)';
      const mana = el.querySelector('.bar.mana i');
      if (mana) mana.style.transform = 'scaleX(0)';
      this.attachUnitHandlers(el, u);
      this.unitLayer.appendChild(el);
    }
    this.unitLayer.style.pointerEvents = 'none';
  },

  attachUnitHandlers(el, u) {
    el.addEventListener('pointerdown', ev => this.beginPointer(ev, { kind: 'unit', unit: u }));
    el.addEventListener('mouseenter', ev => { this.hoverUnit = u; this.showChampTip(ev, u.champId, u.star, u.items); });
    el.addEventListener('mouseleave', () => { this.hoverUnit = null; this.hideTip(); });
    el.addEventListener('contextmenu', ev => { ev.preventDefault(); Game.sell(u); });
  },

  renderBench() {
    const box = document.getElementById('bench');
    box.innerHTML = '';
    for (let i = 0; i < BENCH_SIZE; i++) {
      const slot = U.el('div', 'bench-slot');
      slot.dataset.drop = 'bench'; slot.dataset.index = i;
      const u = Game.player.bench[i];
      if (u) {
        const el = this.unitEl(u, { mana: false });
        el.classList.add('benched');
        el.style.pointerEvents = 'auto';
        this.attachUnitHandlers(el, u);
        slot.appendChild(el);
      }
      box.appendChild(slot);
    }
    const sz = document.getElementById('sellZone');
    sz.dataset.drop = 'sell';
  },

  renderShop() {
    const box = document.getElementById('shop');
    box.innerHTML = '';
    for (let i = 0; i < 5; i++) {
      const id = Game.shop[i];
      if (!id) { box.appendChild(U.el('div', 'card empty')); continue; }
      const c = CHAMP_BY_ID[id];
      const owned = Game.ownedUnits().filter(u => u.champId === id && u.star === 1).length;
      const card = U.el('div', 'card c' + c.cost + (Game.player.gold < c.cost ? ' cant' : ''));
      card.innerHTML =
        `<div class="cn"><i>${c.icon}</i>${U.esc(c.name)}</div>` +
        `<div class="ct">${c.traits.map(t => `<b>${TRAITS[t].icon} ${TRAITS[t].name}</b>`).join('')}</div>` +
        `<div class="cc">● ${c.cost}</div>` +
        (owned ? `<div class="own">${owned}/3</div>` : '');
      card.addEventListener('click', () => {
        if (this.swallowClick) { this.swallowClick = false; return; }
        if (Game.buy(i)) this.pulse(card);
      });
      card.addEventListener('mouseenter', e => this.showChampTip(e, id, 1));
      card.addEventListener('mouseleave', () => this.hideTip());
      this.addLongPress(card, e => { this.showChampTip(e, id, 1); this.pinTip(e); });
      box.appendChild(card);
    }
  },

  pulse(el) { el.style.transform = 'scale(.9)'; setTimeout(() => { el.style.transform = ''; }, 90); },

  /* ---------------- pointer gestures ----------------
     Mouse drags start immediately. Touch waits: a short press opens the
     inspector, movement past a few pixels starts the drag instead. */
  beginPointer(ev, payload) {
    if (Game.phase !== 'plan') return;
    if (ev.button > 0) return;
    if (ev.pointerType === 'mouse') { this.startDrag(ev, payload); return; }
    ev.preventDefault();
    const sx = ev.clientX, sy = ev.clientY;
    let done = false;
    const cleanup = () => {
      clearTimeout(timer);
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', up);
    };
    const timer = setTimeout(() => {
      if (done) return;
      done = true; cleanup();
      this.swallowClick = true;
      const at = { clientX: sx, clientY: sy };
      if (payload.kind === 'unit') this.pinTipForUnit(at, payload.unit);
      else { this.showItemTip(at, payload.id); this.pinTip(at); }
    }, 340);
    const move = e => {
      if (done) return;
      if (Math.hypot(e.clientX - sx, e.clientY - sy) > 10) {
        done = true; cleanup(); this.startDrag(e, payload);
      }
    };
    const up = () => { if (done) return; done = true; cleanup(); };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', up);
  },

  /** press-and-hold to inspect something that is not draggable (shop cards) */
  addLongPress(el, showFn) {
    el.addEventListener('pointerdown', ev => {
      if (ev.pointerType === 'mouse') return;
      const sx = ev.clientX, sy = ev.clientY;
      const cleanup = () => {
        clearTimeout(timer);
        window.removeEventListener('pointermove', move);
        window.removeEventListener('pointerup', cleanup);
        window.removeEventListener('pointercancel', cleanup);
      };
      const timer = setTimeout(() => {
        cleanup(); this.swallowClick = true; showFn({ clientX: sx, clientY: sy });
      }, 340);
      const move = e => { if (Math.hypot(e.clientX - sx, e.clientY - sy) > 12) cleanup(); };
      window.addEventListener('pointermove', move);
      window.addEventListener('pointerup', cleanup);
      window.addEventListener('pointercancel', cleanup);
    });
  },

  /** plain tap opens the inspector for read-only rows (traits, rival captains) */
  addTapInfo(el, showFn) {
    el.addEventListener('click', ev => { if (this.touch) showFn(ev); });
  },

  /* ---------------- drag & drop ---------------- */
  startDrag(ev, payload) {
    if (Game.phase !== 'plan') return;
    if (ev.button > 0) return;
    ev.preventDefault();
    this.hideTip();
    this.drag = payload;
    document.body.classList.add('dragging');
    this.unitLayer.style.pointerEvents = 'none';

    const g = this.ghost;
    if (payload.kind === 'item') {
      g.innerHTML = `<div class="item ${ITEMS[payload.id].comp ? '' : 'forged'}" style="width:40px;height:40px;font-size:20px">${ITEMS[payload.id].icon}</div>`;
    } else {
      const c = CHAMP_BY_ID[payload.unit.champId];
      g.innerHTML = `<div class="unit t${c.cost}"><div class="body">${c.icon}</div></div>`;
    }
    // on touch the ghost floats above the finger, and that is where it drops
    this.dragDY = (ev.pointerType === 'mouse') ? 0 : -52;
    g.classList.remove('hidden');
    this.moveGhost(ev.clientX, ev.clientY);

    const move = e => { this.moveGhost(e.clientX, e.clientY); this.highlight(e.clientX, e.clientY + this.dragDY); };
    const up = e => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', up);
      this.endDrag(e.clientX, e.clientY + this.dragDY);
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', up);
  },

  moveGhost(x, y) {
    this.ghost.style.left = x + 'px';
    this.ghost.style.top = (y + (this.dragDY || 0)) + 'px';
  },

  targetAt(x, y) {
    const el = document.elementFromPoint(x, y);
    if (!el) return null;
    const t = el.closest('[data-drop]');
    if (!t) return null;
    if (t.dataset.drop === 'cell') return { type: 'board', col: +t.dataset.col, row: +t.dataset.row, el: t };
    if (t.dataset.drop === 'bench') return { type: 'bench', index: +t.dataset.index, el: t };
    if (t.dataset.drop === 'sell') return { type: 'sell', el: t };
    return null;
  },

  highlight(x, y) {
    document.querySelectorAll('.drop').forEach(e => e.classList.remove('drop'));
    const t = this.targetAt(x, y);
    if (t && t.el) t.el.classList.add('drop');
    if (this.drag && this.drag.kind === 'unit') {
      const sz = document.getElementById('sellZone');
      const v = CHAMP_BY_ID[this.drag.unit.champId].cost * Math.pow(3, this.drag.unit.star - 1);
      sz.querySelector('.sz-txt').innerHTML = 'SELL FOR<br><span class="price">● ' + v + '</span>';
    }
  },

  endDrag(x, y) {
    const t = this.targetAt(x, y);
    const d = this.drag;
    this.drag = null;
    this.ghost.classList.add('hidden');
    document.body.classList.remove('dragging');
    document.querySelectorAll('.drop').forEach(e => e.classList.remove('drop'));
    document.getElementById('sellZone').querySelector('.sz-txt').innerHTML = 'DROP<br>TO SELL';
    if (!d || !t) { this.renderAll(); return; }

    if (d.kind === 'unit') {
      if (t.type === 'sell') Game.sell(d.unit);
      else Game.moveUnit(d.unit, t);
    } else if (d.kind === 'item') {
      let unit = null;
      if (t.type === 'board') unit = Game.cellOccupant(t.col, t.row);
      else if (t.type === 'bench') unit = Game.player.bench[t.index];
      if (unit) Game.equipItem(d.id, unit);
    }
    this.renderAll();
  },

  /* ---------------- tooltips ---------------- */
  showTip(ev, html) {
    const t = this.tooltip;
    t.innerHTML = html;
    t.classList.remove('hidden');
    this.positionTip(ev);
  },
  positionTip(ev) {
    const t = this.tooltip;
    const r = t.getBoundingClientRect();
    let x = ev.clientX + 18, y = ev.clientY + 12;
    if (x + r.width > innerWidth - 8) x = ev.clientX - r.width - 18;
    if (y + r.height > innerHeight - 8) y = innerHeight - r.height - 8;
    t.style.left = Math.max(6, x) + 'px'; t.style.top = Math.max(6, y) + 'px';
  },
  hideTip() {
    this.tooltip.classList.add('hidden');
    this.tooltip.classList.remove('pinned');
    if (this._tipOff) { window.removeEventListener('pointerdown', this._tipOff, true); this._tipOff = null; }
  },

  /** keep an inspector open until the next tap elsewhere (touch) */
  pinTip(ev) {
    const t = this.tooltip;
    t.classList.add('pinned');
    this.positionTip(ev);
    if (this._tipOff) window.removeEventListener('pointerdown', this._tipOff, true);
    this._tipOff = e => {
      if (t.contains(e.target)) return;
      e.preventDefault(); e.stopPropagation();
      this.hideTip();
    };
    setTimeout(() => { if (this._tipOff) window.addEventListener('pointerdown', this._tipOff, true); }, 0);
  },

  /** inspector for a pirate you own - gets a sell button on touch */
  pinTipForUnit(ev, u) {
    this.showChampTip(ev, u.champId, u.star, u.items);
    if (Game.phase === 'plan') {
      const v = CHAMP_BY_ID[u.champId].cost * Math.pow(3, u.star - 1);
      const b = U.el('button', 'tip-sell', 'SELL FOR ● ' + v);
      b.addEventListener('click', () => { Game.sell(u); this.hideTip(); });
      this.tooltip.appendChild(b);
    }
    this.pinTip(ev);
  },

  showChampTip(ev, champId, star, items) {
    const c = CHAMP_BY_ID[champId];
    const st = statsFor(c, star || 1);
    const html =
      `<div class="tt-head"><div class="tt-ico">${c.icon}</div>` +
      `<div><div class="tt-name">${U.esc(c.name)}</div>` +
      `<div style="font-size:10px;color:#7c93a4">${U.romanStar(star || 1)}</div></div>` +
      `<div class="tt-cost">● ${c.cost}</div></div>` +
      `<div class="tt-traits">${c.traits.map(t => `<span>${TRAITS[t].icon} ${TRAITS[t].name}</span>`).join('')}</div>` +
      `<div class="tt-stats">` +
      `<div>Health <b>${st.maxHp}</b></div><div>Attack Damage <b>${st.ad}</b></div>` +
      `<div>Attack Speed <b>${st.as.toFixed(2)}</b></div><div>Range <b>${st.range}</b></div>` +
      `<div>Armor <b>${st.armor}</b></div><div>Magic Resist <b>${st.mr}</b></div>` +
      `<div>Mana <b>${st.manaStart}/${st.maxMana || '—'}</b></div>` +
      `</div>` +
      (c.cost > 0 ? `<div class="tt-ab"><div class="abn">${U.esc(c.ab.name)}<em>${st.maxMana ? st.manaStart + '/' + st.maxMana + ' mana' : ''}</em></div>` +
        `<div class="tt-desc">${U.fmtDesc(c.ab.desc, c.ab.vals, star || null)}</div></div>` : '') +
      ((items && items.length) ? `<div class="tt-break">Carrying: ${items.map(i => ITEMS[i].icon + ' ' + ITEMS[i].name).join(', ')}</div>` : '');
    this.showTip(ev, html);
  },

  showTraitTip(ev, tr, cur) {
    const html =
      `<div class="tt-head"><div class="tt-ico">${tr.icon}</div>` +
      `<div><div class="tt-name">${tr.name}</div>` +
      `<div style="font-size:10px;color:#7c93a4">${tr.kind === 'origin' ? 'Origin' : 'Class'} · ${cur ? cur.count : 0} fielded</div></div></div>` +
      `<div class="tt-desc">${U.fmtDesc(tr.desc, tr.vals, cur && cur.ti >= 0 ? cur.ti + 1 : null)}</div>` +
      `<div class="tt-break">${tr.breaks.map((b, i) =>
        `<div class="${cur && cur.ti === i ? 'on' : ''}">${b} — ${this.breakSummary(tr, i)}</div>`).join('')}</div>`;
    this.showTip(ev, html);
  },

  breakSummary(tr, i) {
    const parts = [];
    for (const k in tr.vals) {
      const v = tr.vals[k];
      if (Array.isArray(v) && v[i] !== undefined) parts.push(k + ' ' + v[i]);
    }
    return parts.join(', ');
  },

  showItemTip(ev, id) {
    const it = ITEMS[id];
    const recipe = it.from ? `<div class="tt-break">Forged from ${it.from.map(f => ITEMS[f].icon + ' ' + ITEMS[f].name).join(' + ')}</div>` :
      `<div class="tt-break">Component — combine two on one unit to forge.</div>`;
    this.showTip(ev,
      `<div class="tt-head"><div class="tt-ico">${it.icon}</div><div class="tt-name">${it.name}</div></div>` +
      `<div class="tt-desc">${it.desc}</div>${recipe}`);
  },

  showBotTip(ev, bot) {
    const tr = bot.traitSummary().slice(0, 5);
    const units = bot.boardUnits().slice(0, 10);
    this.showTip(ev,
      `<div class="tt-head"><div class="tt-ico">${bot.icon}</div>` +
      `<div><div class="tt-name">${U.esc(bot.name)}</div>` +
      `<div style="font-size:10px;color:#7c93a4">Level ${bot.level} · ${Math.max(0, bot.hp)} hull</div></div></div>` +
      `<div class="tt-traits">${tr.map(t => `<span>${TRAITS[t.id].icon} ${TRAITS[t.id].name} ${t.n}</span>`).join('') || '<span>no traits yet</span>'}</div>` +
      `<div class="tt-desc">${units.map(u => CHAMP_BY_ID[u.champId].icon + ' ' + CHAMP_BY_ID[u.champId].name + (u.star > 1 ? ' ' + U.romanStar(u.star) : '')).join('<br>') || 'An empty deck.'}</div>`);
  },

  /* ---------------- combat rendering ---------------- */
  beginCombatView() {
    this.unitLayer.innerHTML = '';
    this.fxLayer.innerHTML = '';
    this.combatEls.clear();
    for (const u of Game.sim.units) {
      const el = this.unitEl(u, { foe: u.team === 1 });
      el.style.left = u.x + 'px'; el.style.top = u.y + 'px';
      this.unitLayer.appendChild(el);
      this.combatEls.set(u.uid, el);
    }
    this.unitLayer.style.pointerEvents = 'none';
  },

  combatFrame() {
    const sim = Game.sim;
    if (!sim) return;
    for (const u of sim.units) {
      const el = this.combatEls.get(u.uid);
      if (!el) continue;
      if (!u.alive) { el.classList.add('dead'); continue; }
      el.classList.remove('dead');
      el.style.left = u.x + 'px'; el.style.top = u.y + 'px';
      const hp = el.querySelector('.bar.hp i');
      hp.style.transform = 'scaleX(' + U.clamp(u.hp / u.maxHp, 0, 1) + ')';
      const sh = el.querySelector('.bar.hp u');
      sh.style.width = U.clamp(u.shield / u.maxHp, 0, 1) * 100 + '%';
      const mana = el.querySelector('.bar.mana i');
      if (mana) mana.style.transform = 'scaleX(' + (u.maxMana ? U.clamp(u.mana / u.maxMana, 0, 1) : 0) + ')';
      el.classList.toggle('casting', u.casting > 0);
      el.classList.toggle('stunned', u.stunT > 0);
    }
    this.drainFx();
  },

  drainFx() {
    const sim = Game.sim;
    if (!sim || !sim.fxq.length) return;
    const q = sim.fxq;
    sim.fxq = [];
    for (const f of q) this.spawnFx(f);
  },

  spawnFx(f) {
    const layer = this.fxLayer;
    if (layer.childElementCount > 240 && f.kind !== 'text') return;   // keep 4x speed cheap
    let el = null, life = 500;
    switch (f.kind) {
      case 'text':
        el = U.el('div', 'fx-text ' + (f.cls || ''), f.text);
        el.style.left = f.x + 'px'; el.style.top = (f.y - 18) + 'px';
        life = 900; break;
      case 'shot': case 'tracer': case 'chain': case 'beam': {
        if (f.sx === null) return;
        el = U.el('div', 'fx-line');
        const dx = f.x - f.sx, dy = f.y - f.sy;
        el.style.left = f.sx + 'px'; el.style.top = f.sy + 'px';
        el.style.width = Math.hypot(dx, dy) + 'px';
        el.style.transform = 'rotate(' + Math.atan2(dy, dx) + 'rad)';
        el.style.background = 'linear-gradient(90deg,transparent,' + f.color + ')';
        if (f.kind === 'beam') { el.style.height = '5px'; el.style.boxShadow = '0 0 12px ' + f.color; }
        if (f.kind === 'chain') { el.style.height = '3px'; el.style.borderTop = '1px dashed ' + f.color; }
        life = 340; break;
      }
      case 'hit': case 'slash':
        el = U.el('div', 'fx-slash');
        el.style.left = f.x + 'px'; el.style.top = f.y + 'px';
        el.style.borderColor = f.color;
        life = 320; break;
      case 'bolt': {
        el = U.el('div', 'fx-bolt');
        el.style.left = f.x + 'px'; el.style.top = f.y + 'px';
        el.style.height = '90px';
        el.style.background = 'linear-gradient(' + f.color + ',#fff)';
        el.style.boxShadow = '0 0 14px ' + f.color;
        life = 400; break;
      }
      case 'shock': case 'nova': case 'pop': case 'cast': case 'revive': case 'blink': case 'stun': case 'drain': case 'wave': case 'death': {
        if (f.kind === 'death') return;
        el = U.el('div', 'fx-ring');
        el.style.left = f.x + 'px'; el.style.top = f.y + 'px';
        el.style.borderColor = f.color;
        if (f.kind === 'nova' || f.kind === 'wave') el.style.borderWidth = '4px';
        if (f.kind === 'pop' || f.kind === 'cast') el.style.animationDuration = '.35s';
        life = 520; break;
      }
      default: return;
    }
    if (!el) return;
    layer.appendChild(el);
    setTimeout(() => el.remove(), life);
  },

  banner(text, color) {
    const b = document.getElementById('combatBanner');
    b.textContent = text;
    b.style.color = color;
    b.classList.remove('show');
    void b.offsetWidth;
    b.classList.add('show');
  },

  /* ---------------- modals ---------------- */
  modal(html, onClose) {
    document.body.classList.remove('drawer-open');   // never leave the sheet open behind a modal
    const root = document.getElementById('modalRoot');
    const box = document.getElementById('modalBox');
    box.innerHTML = html;
    root.classList.remove('hidden');
    this._modalClose = onClose;
    return box;
  },
  closeModal() {
    document.getElementById('modalRoot').classList.add('hidden');
    if (this._modalClose) { const f = this._modalClose; this._modalClose = null; f(); }
  },

  openArmory() {
    const offers = Game.armoryOffer;
    const box = this.modal(
      `<h2>The Armoury</h2><p>Salvage from the wreck — take one. (+2 gold)</p>` +
      `<div class="armory-row">${offers.map((id, i) => {
        const it = ITEMS[id];
        return `<div class="armory-card" data-i="${i}"><div class="ai">${it.icon}</div>` +
          `<div class="an">${it.name}</div><div class="ad">${it.desc}</div></div>`;
      }).join('')}</div>`);
    box.querySelectorAll('.armory-card').forEach(c => {
      c.addEventListener('click', () => {
        const id = offers[+c.dataset.i];
        document.getElementById('modalRoot').classList.add('hidden');
        Game.takeArmory(id);
      });
    });
  },

  openHelp() {
    this.modal(
      `<h2>How to Sail</h2>` +
      `<div class="help-grid">` +
      `<h3>The Loop</h3>Buy pirates from the shop, drag them onto your half of the board, and your crew fights automatically. ` +
      `Lose a fight and your <b>hull</b> takes damage. Last captain afloat wins.` +
      `<h3>Upgrading</h3>Collect <b>three copies</b> of the same pirate to merge them into a ★★ version — three of those make ★★★. ` +
      `Copies on the bench and board both count.` +
      `<h3>Traits</h3>Every pirate has an <b>Origin</b> and a <b>Class</b>. Fielding enough <i>different</i> pirates sharing a trait ` +
      `activates powerful fleet-wide bonuses. Hover the manifest on the left to read them.` +
      `<h3>Gold</h3>You earn 5 gold a round, plus up to 5 <b>interest</b> (1 per 10 banked, max 5), plus <b>streak</b> bonuses ` +
      `for consecutive wins or losses. Refreshing the shop costs 2; buying 4 XP costs 4.` +
      `<h3>Items</h3>Monster rounds drop components. Drag two components onto the same pirate to <b>forge</b> a full item — ` +
      `each pirate carries up to three. The Armoury at the end of each stage offers a finished item.` +
      `<h3>Controls</h3>` +
      `<b>Drag</b> units between bench and board · <b>Right-click</b> a unit to sell · <b>D</b> refresh shop · ` +
      `<b>F</b> buy XP · <b>E</b> sell hovered unit · <b>Space</b> start the battle early · <b>1/2/4</b> battle speed` +
      `</div><button class="modal-btn" id="helpOk">WEIGH ANCHOR</button>`);
    document.getElementById('helpOk').addEventListener('click', () => this.closeModal());
  },

  openGameOver() {
    const p = Game.player;
    const won = p.place === 1;
    this.modal(
      `<h2>${won ? 'The Sea Is Yours' : 'Davy Jones Calls'}</h2>` +
      `<div class="result-line ${won ? 'place-1' : ''}">${Game.ordinal(p.place)} place</div>` +
      `<p>${won ? 'Every rival fleet lies on the seabed. The horizon belongs to you.' :
        'Your hull gave out at stage ' + Game.stage + '. The crew salutes you as you sink.'}</p>` +
      `<button class="modal-btn" id="againBtn">SAIL AGAIN</button>`);
    document.getElementById('againBtn').addEventListener('click', () => {
      document.getElementById('modalRoot').classList.add('hidden');
      Game.init();
      UI.renderAll();
    });
  },

  /* ---------------- global input ---------------- */
  bindGlobal() {
    document.getElementById('rerollBtn').addEventListener('click', () => Game.reroll());
    document.getElementById('buyXpBtn').addEventListener('click', () => Game.buyXp());
    document.getElementById('lockBtn').addEventListener('click', () => { Game.shopLocked = !Game.shopLocked; this.renderTop(); });
    document.getElementById('readyBtn').addEventListener('click', () => Main.forceCombat());
    document.getElementById('helpBtn').addEventListener('click', () => this.openHelp());
    document.getElementById('helpBtn2').addEventListener('click', () => {
      document.body.classList.remove('drawer-open'); this.openHelp();
    });
    document.getElementById('drawerBtn').addEventListener('click', () => {
      document.body.classList.toggle('drawer-open'); this.hideTip();
    });
    document.getElementById('drawerScrim').addEventListener('click', () =>
      document.body.classList.remove('drawer-open'));
    document.querySelectorAll('.spd').forEach(b => b.addEventListener('click', () => {
      Game.speed = +b.dataset.speed;
      document.querySelectorAll('.spd').forEach(x => x.classList.toggle('on', x === b));
    }));
    window.addEventListener('keydown', e => {
      if (e.repeat) return;
      const k = e.key.toLowerCase();
      if (k === 'd') Game.reroll();
      else if (k === 'f') Game.buyXp();
      else if (k === 'e' && this.hoverUnit) { Game.sell(this.hoverUnit); this.hoverUnit = null; this.hideTip(); }
      else if (k === ' ') { e.preventDefault(); Main.forceCombat(); }
      else if (k === '1' || k === '2' || k === '4') {
        Game.speed = +k;
        document.querySelectorAll('.spd').forEach(x => x.classList.toggle('on', +x.dataset.speed === Game.speed));
      }
    });
    window.addEventListener('contextmenu', e => { if (e.target.closest('#boardWrap,#bench')) e.preventDefault(); });
  }
};
