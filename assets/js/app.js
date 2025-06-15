import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let Hooks = {};

Hooks.CanvasHook = {
  mounted() {
    this.canvas = this.el.querySelector("#physics-canvas");
    this.ctx = this.canvas.getContext("2d");
    this.particles = new Map();

    this.camera = {
        pan: { x: this.canvas.width / 2, y: this.canvas.height / 2 },
        zoom: 1.0,
        rotation: 0, // NOVO: Ângulo da câmera em radianos
        isPanning: false,
        lastMouse: { x: 0, y: 0 },
        MIN_ZOOM: 0.4,
        MAX_ZOOM: 4.0,
        panState: { up: false, down: false, left: false, right: false },
        PAN_SPEED: 400 
    };

    this.cueState = {
        status: 'inactive',
        start: { x: 0, y: 0 },
        end: { x: 0, y: 0 },
        animation: {
            startTime: 0,
            duration: 150,
            force: { x: 0, y: 0 },
            initialPullDistance: 0,
        }
    };

    this.boundHandleMouseMove = this.handleMouseMove.bind(this);
    this.boundHandleMouseUp = this.handleMouseUp.bind(this);
    this.boundHandleTouchMove = this.handleTouchMove.bind(this);
    this.boundHandleTouchEnd = this.handleTouchEnd.bind(this);
    this.boundHandleWheel = this.handleWheel.bind(this);

    this.canvas.addEventListener("mousedown", this.handleMouseDown.bind(this));
    this.canvas.addEventListener("touchstart", this.handleTouchStart.bind(this), { passive: false });
    this.canvas.addEventListener("wheel", this.boundHandleWheel);
    this.canvas.addEventListener('contextmenu', event => event.preventDefault());

    this.el.querySelector("#zoom-in-btn").addEventListener("click", () => this.zoom(1.2));
    this.el.querySelector("#zoom-out-btn").addEventListener("click", () => this.zoom(0.8));
    this.el.querySelector("#reset-view-btn").addEventListener("click", () => this.resetView());
    this.el.querySelector("#rotate-btn").addEventListener("click", () => this.rotateCamera());

    this.setupDPadListeners();

    this.handleEvent("particle_moved", (payload) => this.particles.set(payload.id, payload));
    this.handleEvent("particle_removed", (payload) => {
      if (this.particles.has(payload.id)) this.particles.delete(payload.id);
    });

    this.lastFrameTime = performance.now();
    this.animationFrameId = requestAnimationFrame(() => this.drawFrame());
  },

  destroyed() {
    if (this.animationFrameId) cancelAnimationFrame(this.animationFrameId);
    this.removeGlobalListeners();
    this.canvas.removeEventListener("wheel", this.boundHandleWheel);
  },

  // MUDANÇA: A função de rotação agora manipula o ângulo da câmera.
  rotateCamera() {
    this.camera.rotation += Math.PI / 2; // Gira 90 graus
  },

  setupDPadListeners() {
    const dPadMap = { "d-pad-up": "up", "d-pad-down": "down", "d-pad-left": "left", "d-pad-right": "right" };
    for (const [id, direction] of Object.entries(dPadMap)) {
        const button = this.el.querySelector(`#${id}`);
        const setPanState = (state) => { this.camera.panState[direction] = state; };
        button.addEventListener("mousedown", () => setPanState(true));
        button.addEventListener("touchstart", (e) => { e.preventDefault(); setPanState(true); });
        button.addEventListener("mouseup", () => setPanState(false));
        button.addEventListener("touchend", (e) => { e.preventDefault(); setPanState(false); });
        button.addEventListener("mouseleave", () => setPanState(false));
    }
  },

  updatePanFromDpad(deltaTime) {
    const { panState, PAN_SPEED, zoom, rotation } = this.camera;
    const moveAmount = (PAN_SPEED * deltaTime) / zoom;
    
    let moveX = 0;
    let moveY = 0;

    if (panState.up) moveY -= moveAmount;
    if (panState.down) moveY += moveAmount;
    if (panState.left) moveX -= moveAmount;
    if (panState.right) moveX += moveAmount;
    
    if (moveX === 0 && moveY === 0) return;

    // MUDANÇA: Rotaciona o vetor de movimento para alinhar com a câmera
    const cosR = Math.cos(rotation);
    const sinR = Math.sin(rotation);

    const worldMoveX = moveX * cosR - moveY * sinR;
    const worldMoveY = moveX * sinR + moveY * cosR;

    this.camera.pan.x += worldMoveX;
    this.camera.pan.y += worldMoveY;
  },

  // MUDANÇA: A transformação de tela para mundo agora considera a rotação.
  screenToWorld({ x, y }) {
    const { pan, zoom, rotation } = this.camera;
    const { width, height } = this.canvas;
    
    // 1. Coordenadas relativas ao centro da tela
    const relX = x - width / 2;
    const relY = y - height / 2;

    // 2. Desfaz o zoom
    const unscaledX = relX / zoom;
    const unscaledY = relY / zoom;

    // 3. Desfaz a rotação
    const cosR = Math.cos(-rotation); // Rotação inversa
    const sinR = Math.sin(-rotation);
    const rotatedX = unscaledX * cosR - unscaledY * sinR;
    const rotatedY = unscaledX * sinR + unscaledY * cosR;

    // 4. Adiciona o pan da câmera para obter as coordenadas do mundo
    const worldX = rotatedX + pan.x;
    const worldY = rotatedY + pan.y;

    return { x: worldX, y: worldY };
  },

  zoom(factor) {
      const mousePos = { x: this.canvas.width / 2, y: this.canvas.height / 2 };
      const worldPosBeforeZoom = this.screenToWorld(mousePos);
      this.camera.zoom = Math.max(this.camera.MIN_ZOOM, Math.min(this.camera.MAX_ZOOM, this.camera.zoom * factor));
      const worldPosAfterZoom = this.screenToWorld(mousePos);
      this.camera.pan.x += worldPosBeforeZoom.x - worldPosAfterZoom.x;
      this.camera.pan.y += worldPosBeforeZoom.y - worldPosAfterZoom.y;
  },

  resetView() {
      this.camera.pan = { x: 1000 / 2, y: 500 / 2 };
      this.camera.zoom = 1.0;
      this.camera.rotation = 0; // Também reseta a rotação
  },
  
  // MUDANÇA: A renderização agora aplica a rotação da câmera.
  drawFrame() {
    const now = performance.now();
    const deltaTime = (now - this.lastFrameTime) / 1000;
    this.lastFrameTime = now;
    this.updatePanFromDpad(deltaTime);

    const { ctx } = this;
    const { width, height } = this.canvas;
    const { pan, zoom, rotation } = this.camera;

    ctx.clearRect(0, 0, width, height);
    ctx.save();

    // A ordem da transformação é crucial!
    ctx.translate(width / 2, height / 2); // 1. Vai para o centro da tela
    ctx.rotate(rotation);                 // 2. Rotaciona a "câmera"
    ctx.scale(zoom, zoom);                // 3. Aplica o zoom
    ctx.translate(-pan.x, -pan.y);        // 4. Move o mundo para a posição da câmera

    this.drawTable(1000, 500);

    this.particles.forEach((particle) => {
      const { pos: [x, y], radius, color } = particle;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fillStyle = color;
      ctx.fill();
      ctx.strokeStyle = 'black';
      ctx.lineWidth = 1 / zoom;
      ctx.stroke();
    });
    
    if (this.cueState.status === 'aiming') this.drawCue();
    else if (this.cueState.status === 'striking') this.animateAndStrike();
    
    ctx.restore();
    this.animationFrameId = requestAnimationFrame(() => this.drawFrame());
  },

  // Funções restantes (drawTable, drawCue, handlers, etc.)
  // Nenhuma mudança necessária abaixo desta linha
  drawTable(worldWidth, worldHeight) {
    const { ctx } = this;
    ctx.fillStyle = "#1a6d38";
    ctx.fillRect(0, 0, worldWidth, worldHeight);
    ctx.fillStyle = "#8B4513";
    const borderWidth = 30;
    ctx.fillRect(0, 0, worldWidth, borderWidth);
    ctx.fillRect(0, worldHeight - borderWidth, worldWidth, borderWidth);
    ctx.fillRect(0, 0, borderWidth, worldHeight);
    ctx.fillRect(worldWidth - borderWidth, 0, borderWidth, worldHeight);
    ctx.fillStyle = "black";
    const pocketRadius = 25;
    const pockets = [
      [borderWidth, borderWidth], [worldWidth - borderWidth, borderWidth],
      [borderWidth, worldHeight - borderWidth], [worldWidth - borderWidth, worldHeight - borderWidth],
      [worldWidth / 2, borderWidth], [worldWidth / 2, worldHeight - borderWidth]
    ];
    pockets.forEach(([x, y]) => {
      ctx.beginPath();
      ctx.arc(x, y, pocketRadius, 0, Math.PI * 2);
      ctx.fill();
    });
  },

  drawCue(pullbackOverride = null) {
    const { ctx } = this;
    const { start, end } = this.cueState;
    const whiteBall = Array.from(this.particles.values()).find(p => p.color === "white");
    if (!whiteBall) { this.cueState.status = 'inactive'; return; }

    const CUE_LENGTH = 450, CUE_BUTT_WIDTH = 16, CUE_TIP_WIDTH = 7, PULLBACK_OFFSET = 10;
    const pullX = end.x - start.x, pullY = end.y - start.y;
    const pullDistance = pullbackOverride !== null ? pullbackOverride : Math.sqrt(pullX * pullX + pullY * pullY);
    const dirX = -pullX, dirY = -pullY;
    const dirLen = Math.sqrt(dirX * dirX + dirY * dirY);
    if (dirLen === 0) return;
    const normX = dirX / dirLen, normY = dirY / dirLen;

    if (this.cueState.status === 'aiming') {
        ctx.save();
        ctx.beginPath();
        ctx.moveTo(start.x, start.y);
        ctx.setLineDash([5 / this.camera.zoom, 10 / this.camera.zoom]);
        ctx.lineTo(start.x + normX * 2000, start.y + normY * 2000);
        ctx.strokeStyle = "rgba(255, 255, 255, 0.6)";
        ctx.lineWidth = 2 / this.camera.zoom;
        ctx.stroke();
        ctx.restore();
    }

    const tipX = start.x - normX * (whiteBall.radius + PULLBACK_OFFSET + pullDistance);
    const tipY = start.y - normY * (whiteBall.radius + PULLBACK_OFFSET + pullDistance);
    const buttX = tipX - normX * CUE_LENGTH, buttY = tipY - normY * CUE_LENGTH;
    const perpX = -normY, perpY = normX;
    const p1 = { x: tipX + perpX * CUE_TIP_WIDTH / 2, y: tipY + perpY * CUE_TIP_WIDTH / 2 }, p2 = { x: tipX - perpX * CUE_TIP_WIDTH / 2, y: tipY - perpY * CUE_TIP_WIDTH / 2 }, p3 = { x: buttX - perpX * CUE_BUTT_WIDTH / 2, y: buttY - perpY * CUE_BUTT_WIDTH / 2 }, p4 = { x: buttX + perpX * CUE_BUTT_WIDTH / 2, y: buttY + perpY * CUE_BUTT_WIDTH / 2 };
    
    const gradient = ctx.createLinearGradient(p2.x, p2.y, p4.x, p4.y);
    gradient.addColorStop(0, '#A0522D'); gradient.addColorStop(0.5, '#D2B48C'); gradient.addColorStop(1, '#8B4513');
    ctx.fillStyle = gradient;
    ctx.beginPath(); ctx.moveTo(p1.x, p1.y); ctx.lineTo(p2.x, p2.y); ctx.lineTo(p3.x, p3.y); ctx.lineTo(p4.x, p4.y); ctx.closePath();
    ctx.fill();
    ctx.strokeStyle = "rgba(0, 0, 0, 0.4)"; ctx.lineWidth = 1 / this.camera.zoom; ctx.stroke();
  },

  animateAndStrike() {
    const { animation } = this.cueState;
    const elapsedTime = performance.now() - animation.startTime;
    const progress = Math.min(elapsedTime / animation.duration, 1);
    const easedProgress = 1 - Math.pow(1 - progress, 3);
    const currentPullDistance = animation.initialPullDistance * (1 - easedProgress);
    this.drawCue(currentPullDistance);
    if (progress >= 1) {
      this.pushEvent("apply_force", animation.force);
      this.cueState.status = 'inactive';
    }
  },
  
  getMousePos(e) {
      const rect = this.canvas.getBoundingClientRect();
      return { x: e.clientX - rect.left, y: e.clientY - rect.top };
  },

  handleMouseDown(e) {
    const mousePos = this.getMousePos(e);
    if (e.button === 0) {
        this.startAiming(this.screenToWorld(mousePos));
    } else {
        e.preventDefault();
        this.camera.isPanning = true;
        this.camera.lastMouse = mousePos;
        this.canvas.style.cursor = 'grabbing';
        this.addGlobalListeners();
    }
  },

  handleMouseMove(e) {
    const mousePos = this.getMousePos(e);
    if (this.camera.isPanning) {
        // O pan com o mouse também precisa respeitar a rotação
        const cosR = Math.cos(this.camera.rotation);
        const sinR = Math.sin(this.camera.rotation);
        const dx = (mousePos.x - this.camera.lastMouse.x) / this.camera.zoom;
        const dy = (mousePos.y - this.camera.lastMouse.y) / this.camera.zoom;
        this.camera.pan.x -= dx * cosR + dy * sinR;
        this.camera.pan.y -= dy * cosR - dx * sinR;

    } else if (this.cueState.status === 'aiming') {
        this.updateAim(this.screenToWorld(mousePos));
    }
    this.camera.lastMouse = mousePos;
  },

  handleMouseUp(e) {
    if (e.button !== 0) this.camera.isPanning = false;
    this.canvas.style.cursor = 'grab';
    this.applyStrike();
    this.removeGlobalListeners();
  },
  
  handleWheel(e) {
      e.preventDefault();
      this.zoom(e.deltaY < 0 ? 1.1 : 0.9);
  },

  handleTouchStart(e) {
    e.preventDefault();
    if (e.touches.length === 1) {
        this.startAiming(this.screenToWorld(this.getMousePos(e.touches[0])));
    }
  },

  handleTouchMove(e) {
    e.preventDefault();
    if (this.cueState.status === 'aiming' && e.touches.length === 1) {
      this.updateAim(this.screenToWorld(this.getMousePos(e.touches[0])));
    }
  },

  handleTouchEnd() {
    this.applyStrike();
    this.removeGlobalListeners();
  },
   
  startAiming({x, y}) {
    if (this.cueState.status !== 'inactive' || this.camera.isPanning) return;
    const whiteBall = Array.from(this.particles.values()).find(p => p.color === "white");
    if (whiteBall) {
      const [wx, wy] = whiteBall.pos;
      const distance = Math.sqrt((x - wx)**2 + (y - wy)**2);
      if (distance <= whiteBall.radius + 30 / this.camera.zoom) {
        this.cueState.status = 'aiming';
        this.cueState.start = { x: wx, y: wy };
        this.cueState.end = { x, y };
        this.addGlobalListeners();
      }
    }
  },
  
  updateAim({x, y}) {
    this.cueState.end = { x, y };
  },

  applyStrike() {
    if (this.cueState.status !== 'aiming') return;
    const { start, end } = this.cueState;
    const dx = start.x - end.x, dy = start.y - end.y;
    const forceMultiplier = 0.1; 
    this.cueState.status = 'striking';
    this.cueState.animation.startTime = performance.now();
    this.cueState.animation.force = { x: dx * forceMultiplier, y: dy * forceMultiplier };
    this.cueState.animation.initialPullDistance = Math.sqrt(dx*dx + dy*dy);
  },
  
  addGlobalListeners() {
      window.addEventListener("mousemove", this.boundHandleMouseMove);
      window.addEventListener("mouseup", this.boundHandleMouseUp);
      window.addEventListener("touchmove", this.boundHandleTouchMove, { passive: false });
      window.addEventListener("touchend", this.boundHandleTouchEnd, { passive: false });
  },

  removeGlobalListeners() {
      window.removeEventListener("mousemove", this.boundHandleMouseMove);
      window.removeEventListener("mouseup", this.boundHandleMouseUp);
      window.removeEventListener("touchmove", this.boundHandleTouchMove);
      window.removeEventListener("touchend", this.boundHandleTouchEnd);
  }
};


let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket
