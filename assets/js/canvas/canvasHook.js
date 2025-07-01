import { createInitialCameraState, createInitialCueState } from './state';
import * as cameraModule from './camera';
import * as cueModule from './cue';
import { drawFrame } from './renderer';
import InputHandler from './inputHandler';

export const CanvasHook = {
  mounted() {
    this.particles = new Map();
    this.camera = createInitialCameraState();
    this.cueState = createInitialCueState();
    this.animationFrameId = null;
    this.cameraModule = cameraModule;
    this.cueModule = cueModule;

    this.canvas = this.el.querySelector("#physics-canvas");
    this.ctx = this.canvas.getContext("2d");
    this.canvasWrapper = this.el.querySelector('#canvas-wrapper');
    this.powerBarElement = this.el.querySelector('#power-bar');

    this.inputHandler = new InputHandler(this);
    this.inputHandler.addEventListeners();

    this.handleEvent("initial_state", ({ particles }) => {
      console.log("Received initial state with", particles.length, "particles.");
      this.particles.clear();
      particles.forEach(p => this.updateParticle(p));
      // Inicia o loop de renderização APÓS receber o estado inicial
      this.startGame();
    });
    this.handleEvent("particle_moved", (payload) => this.updateParticle(payload));
    this.handleEvent("particle_removed", (payload) => this.particles.delete(payload.id));
    
    // Solicita o estado inicial assim que o hook é montado
    this.pushEvent("request_initial_state", {});
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
    if (existingParticle) {
      payload.lastRollAngle = existingParticle.lastRollAngle;
      payload.lastTextureOffsetY = existingParticle.lastTextureOffsetY;
    }
    this.particles.set(payload.id, payload);
  },
};