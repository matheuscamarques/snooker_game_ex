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
        rotation: 0,
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

    this.handleEvent("particle_moved", (payload) => {
      // Mantém o estado visual completo da partícula entre as atualizações do servidor.
      const existingParticle = this.particles.get(payload.id);
      if (existingParticle) {
        payload.lastRollAngle = existingParticle.lastRollAngle;
        payload.lastTextureOffsetY = existingParticle.lastTextureOffsetY; // Preserva a posição da textura
      }
      this.particles.set(payload.id, payload);
    });
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
    ctx.translate(width / 2, height / 2);
    ctx.rotate(rotation);
    ctx.scale(zoom, zoom);
    ctx.translate(-pan.x, -pan.y);

    this.drawTable(1000, 500);

    this.particles.forEach((particle) => {
      this.drawBall(particle);
    });
    
    if (this.cueState.status === 'aiming') this.drawCue();
    else if (this.cueState.status === 'striking') this.animateAndStrike();
    
    ctx.restore();
    this.animationFrameId = requestAnimationFrame(() => this.drawFrame());
  },

  drawBall(particle) {
    const { ctx } = this;
    const { pos: [x, y], vel: [vx, vy], radius, color, spin_angle, roll_distance } = particle;
    const { number, type, base_color } = color;

    // --- 1. Determina a orientação e o deslocamento da textura ---
    const speed = Math.sqrt(vx * vx + vy * vy);
    let rollAngle;
    let textureOffsetY;

    if (speed > 0.1) {
        const dirX = vx / speed;
        const dirY = vy / speed;
        rollAngle = Math.atan2(dirY, dirX) - Math.PI / 2;
        textureOffsetY = roll_distance % (Math.PI * 2 * radius);
        
        // Armazena o último estado visual quando a bola está se movendo
        particle.lastRollAngle = rollAngle;
        particle.lastTextureOffsetY = textureOffsetY;
    } else {
        // Usa o último estado visual quando a bola para
        rollAngle = particle.lastRollAngle || 0;
        textureOffsetY = particle.lastTextureOffsetY || 0;
    }

    // --- 2. Desenha a base da bola ---
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    ctx.fillStyle = base_color;
    ctx.fill();

    // --- 3. Desenha a Textura (Listra e Número) ---
    ctx.save();
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    ctx.clip();
    
    ctx.translate(x, y);
    ctx.rotate(rollAngle);
    ctx.rotate(spin_angle);

    const circumference = Math.PI * 2 * radius;

    if (type === 'stripe') {
        const bandHeight = radius * 1.4;
        ctx.fillStyle = 'white';
        ctx.fillRect(-radius, -bandHeight / 2 + textureOffsetY, radius * 2, bandHeight);
        ctx.fillRect(-radius, -bandHeight / 2 + textureOffsetY - circumference, radius * 2, bandHeight);
        ctx.fillRect(-radius, -bandHeight / 2 + textureOffsetY + circumference, radius * 2, bandHeight);
    }

    if (number > 0) {
        const numCircleRadius = radius * 0.6;
        ctx.fillStyle = 'white';
        ctx.beginPath();
        ctx.arc(0, textureOffsetY, numCircleRadius, 0, Math.PI * 2);
        ctx.fill();
        ctx.beginPath();
        ctx.arc(0, textureOffsetY - circumference, numCircleRadius, 0, Math.PI * 2);
        ctx.fill();
        ctx.beginPath();
        ctx.arc(0, textureOffsetY + circumference, numCircleRadius, 0, Math.PI * 2);
        ctx.fill();
        
        ctx.fillStyle = 'black';
        ctx.font = `bold ${radius * 0.95}px Arial`;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(number.toString(), 0, textureOffsetY);
        ctx.fillText(number.toString(), 0, textureOffsetY - circumference);
        ctx.fillText(number.toString(), 0, textureOffsetY + circumference);
    }

    ctx.restore();

    // --- 4. Desenha o Brilho 3D ---
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    const gradient = ctx.createRadialGradient(
      x - radius * 0.3, y - radius * 0.3, radius * 0.1, x, y, radius
    );
    gradient.addColorStop(0, 'rgba(255, 255, 255, 0.7)');
    gradient.addColorStop(0.5, 'rgba(255, 255, 255, 0)');
    gradient.addColorStop(1, 'rgba(0, 0, 0, 0.3)');
    ctx.fillStyle = gradient;
    ctx.fill();

    // --- 5. Desenha o Contorno Final ---
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    ctx.strokeStyle = 'rgba(0, 0, 0, 0.2)';
    ctx.lineWidth = 1 / this.camera.zoom;
    ctx.stroke();
  },

  rotateCamera() {
    this.camera.rotation += Math.PI / 2;
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
    let moveX = 0, moveY = 0;
    if (panState.up) moveY -= moveAmount;
    if (panState.down) moveY += moveAmount;
    if (panState.left) moveX -= moveAmount;
    if (panState.right) moveX += moveAmount;
    if (moveX === 0 && moveY === 0) return;
    const cosR = Math.cos(rotation), sinR = Math.sin(rotation);
    const worldMoveX = moveX * cosR - moveY * sinR, worldMoveY = moveX * sinR + moveY * cosR;
    this.camera.pan.x += worldMoveX;
    this.camera.pan.y += worldMoveY;
  },

  screenToWorld({ x, y }) {
    const { pan, zoom, rotation } = this.camera;
    const { width, height } = this.canvas;
    const relX = x - width / 2, relY = y - height / 2;
    const unscaledX = relX / zoom, unscaledY = relY / zoom;
    const cosR = Math.cos(-rotation), sinR = Math.sin(-rotation);
    const rotatedX = unscaledX * cosR - unscaledY * sinR, rotatedY = unscaledX * sinR + unscaledY * cosR;
    const worldX = rotatedX + pan.x, worldY = rotatedY + pan.y;
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
      this.camera.rotation = 0;
  },

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
    const whiteBall = Array.from(this.particles.values()).find(p => p.color.type === "cue");
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
    ctx.strokeStyle = "rgba(0, 0, 0, 0.4)"; ctx.lineWidth = 1 / this.camera.zoom;
    ctx.stroke();
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
        const cosR = Math.cos(this.camera.rotation), sinR = Math.sin(this.camera.rotation);
        const dx = (mousePos.x - this.camera.lastMouse.x) / this.camera.zoom, dy = (mousePos.y - this.camera.lastMouse.y) / this.camera.zoom;
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
    const whiteBall = Array.from(this.particles.values()).find(p => p.color.type === "cue");
    if (whiteBall) {
      this.pushEvent("hold_ball", 0);
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
