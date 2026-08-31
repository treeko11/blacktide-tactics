/* ============================================================
   MAIN LOOP - drives phases, the fixed-step sim, and rendering
   ============================================================ */
'use strict';

const Main = {
  lastTs: 0,
  acc: 0,
  postCombat: 0,
  resultDelay: 0,
  viewReady: false,
  armoryOpen: false,
  overShown: false,
  renderQueued: false,

  start() {
    UI.init();
    Game.onChange = () => Main.queueRender();
    Game.init();
    UI.renderAll();
    UI.openHelp();
    requestAnimationFrame(Main.frame);
  },

  queueRender() {
    if (this.renderQueued) return;
    this.renderQueued = true;
    requestAnimationFrame(() => { this.renderQueued = false; UI.renderAll(); });
  },

  forceCombat() {
    if (Game.phase !== 'plan') return;
    Game.timer = 0;
  },

  frame(ts) {
    const dt = Math.min(0.1, (ts - Main.lastTs) / 1000 || 0);
    Main.lastTs = ts;
    Main.update(dt);
    requestAnimationFrame(Main.frame);
  },

  update(dt) {
    switch (Game.phase) {

      case 'plan': {
        this.viewReady = false;
        Game.timer -= dt;
        const f = U.clamp(Game.timer / PLAN_TIME, 0, 1);
        document.getElementById('timerBar').style.width = (f * 100) + '%';
        document.getElementById('timerTxt').textContent = Math.max(0, Math.ceil(Game.timer));
        if (Game.timer <= 0) {
          Game.startCombat();
          UI.beginCombatView();
          this.viewReady = true;
          this.acc = 0;
          UI.banner('ENGAGE', '#7fe3ff');
          UI.renderAll();
        }
        break;
      }

      case 'combat': {
        if (!this.viewReady) { UI.beginCombatView(); this.viewReady = true; }
        const sim = Game.sim;
        document.getElementById('timerTxt').textContent = Math.max(0, Math.ceil(COMBAT_TIME_LIMIT - sim.t));
        document.getElementById('timerBar').style.width =
          U.clamp(1 - sim.t / COMBAT_TIME_LIMIT, 0, 1) * 100 + '%';

        if (!sim.done) {
          this.acc += dt * Game.speed;
          let steps = 0;
          while (this.acc >= TICK && steps < 40 && !sim.done) {
            sim.step(); this.acc -= TICK; steps++;
          }
          UI.combatFrame();
          if (sim.done) {
            this.postCombat = 1.3;
            if (sim.winner === 0) UI.banner('VICTORY', '#ffd98a');
            else if (sim.winner === 1) UI.banner('DEFEAT', '#ff6b7d');
            else UI.banner('STALEMATE', '#9fb8c8');
          }
        } else {
          UI.combatFrame();
          this.postCombat -= dt;
          if (this.postCombat <= 0) {
            Game.resolveCombat();
            this.resultDelay = 1.5;
          }
        }
        break;
      }

      case 'result': {
        this.resultDelay -= dt;
        if (this.resultDelay <= 0) {
          Game.sim = null;
          Game.currentOpponent = null;
          Game.advanceRound();
          UI.renderAll();
        }
        break;
      }

      case 'armory': {
        if (!this.armoryOpen) { this.armoryOpen = true; UI.openArmory(); }
        break;
      }

      case 'over': {
        if (!this.overShown) { this.overShown = true; UI.openGameOver(); }
        break;
      }
    }

    if (Game.phase !== 'armory') this.armoryOpen = false;
    if (Game.phase !== 'over') this.overShown = false;
  }
};

window.addEventListener('load', () => Main.start());
