// ============================================================================
// FILE: /assets/js/canvas_hook.js
// DESCRIÇÃO: O hook do Phoenix LiveView que inicializa e gere o canvas.
// ============================================================================

export const CanvasHook = {
  mounted() {
    this.particles = new Map();
    this.camera = createInitialCameraState();
    this.cueState = createInitialCueState();
    this.animationFrameId = null;

    // Importa os módulos para dentro do hook
    this.cameraModule = { screenToWorld, resetView, rotateCamera, zoom, updatePan };
    this.cueModule = { startAiming, updateAim, applyStrike };

    this.canvas = this.el.querySelector("#physics-canvas");
    this.ctx = this.canvas.getContext("2d");
    this.canvasWrapper = this.el.querySelector('#canvas-wrapper');

    this.inputHandler = new InputHandler(this);
    this.inputHandler.addEventListeners();

    // Inicia o loop de renderização e redimensiona o canvas pela primeira vez
    this.startGame();

    // Listeners para eventos do servidor
    this.handleEvent("particle_moved", (payload) => this.updateParticle(payload));
    this.handleEvent("particle_removed", (payload) => this.particles.delete(payload.id));
  },

  startGame() {
    if (this.animationFrameId) return; // Previne múltiplos loops
    console.log("Starting render loop.");
    this.inputHandler.resizeCanvas();
    this.lastFrameTime = performance.now();
    this.animationFrameId = requestAnimationFrame(() => drawFrame(this));
  },

  destroyed() {
    if (this.animationFrameId) {
      cancelAnimationFrame(this.animationFrameId);
    }
    this.inputHandler.removeEventListeners();
  },

  updateParticle(payload) {
    const existingParticle = this.particles.get(payload.id);
    // Mantém o estado de rotação da bola para uma aparência suave quando para
    if (existingParticle) {
      payload.lastRollAngle = existingParticle.lastRollAngle;
      payload.lastTextureOffsetY = existing.lastTextureOffsetY;
    }
    this.particles.set(payload.id, payload);
  },
};