// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let Hooks = {};

Hooks.CanvasHook = {
  // Chamado quando o hook é montado em um elemento DOM.
  mounted() {
    this.canvas = this.el.querySelector("#physics-canvas");
    this.ctx = this.canvas.getContext("2d");
    this.particles = new Map();
    // Estado do taco: 'aiming' (mirando), 'striking' (animando a tacada), 'inactive'
    this.cueState = {
        status: 'inactive', // inactive, aiming, striking
        start: { x: 0, y: 0 },
        end: { x: 0, y: 0 },
        animation: {
            startTime: 0,
            duration: 150, // Duração da animação em ms
            force: { x: 0, y: 0 },
            initialPullDistance: 0,
        }
    };

    // --- BIND dos Handlers para manter o contexto do 'this' ---
    // Isso é crucial para adicionar e remover os listeners corretamente da janela.
    this.boundHandleMouseMove = this.handleMouseMove.bind(this);
    this.boundHandleMouseUp = this.handleMouseUp.bind(this);
    this.boundHandleTouchMove = this.handleTouchMove.bind(this);
    this.boundHandleTouchEnd = this.handleTouchEnd.bind(this);


    // --- Configuração dos Event Listeners INICIAIS ---
    // Apenas os eventos que INICIAM a ação são registrados no canvas.
    this.canvas.addEventListener("mousedown", this.handleMouseDown.bind(this));
    this.canvas.addEventListener("touchstart", this.handleTouchStart.bind(this), { passive: false });

    // Ouve por atualizações de posição do servidor.
    this.handleEvent("particle_moved", (payload) => {
      this.particles.set(payload.id, payload);
    });

    this.handleEvent("particle_removed", (payload) => {
		if (this.particles.has(payload.id)) {
			this.particles.delete(payload.id);
		}
	});

    // --- Início do Loop de Animação ---
    this.animationFrameId = requestAnimationFrame(() => this.drawFrame());
  },

  destroyed() {
    if (this.animationFrameId) {
      cancelAnimationFrame(this.animationFrameId);
    }
    // Garante que os listeners globais sejam removidos se o elemento for destruído.
    this.removeGlobalListeners();
  },

  drawTable() {
    const { ctx, canvas } = this;
    ctx.fillStyle = "#1a6d38";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "#8B4513";
    const borderWidth = 30;
    ctx.fillRect(0, 0, canvas.width, borderWidth);
    ctx.fillRect(0, canvas.height - borderWidth, canvas.width, borderWidth);
    ctx.fillRect(0, 0, borderWidth, canvas.height);
    ctx.fillRect(canvas.width - borderWidth, 0, borderWidth, canvas.height);
    ctx.fillStyle = "black";
    const pocketRadius = 25;
    const pockets = [
      [borderWidth, borderWidth], [canvas.width - borderWidth, borderWidth],
      [borderWidth, canvas.height - borderWidth], [canvas.width - borderWidth, canvas.height - borderWidth],
      [canvas.width / 2, borderWidth], [canvas.width / 2, canvas.height - borderWidth]
    ];
    pockets.forEach(([x, y]) => {
      ctx.beginPath();
      ctx.arc(x, y, pocketRadius, 0, Math.PI * 2);
      ctx.fill();
    });
  },

  // A função principal de renderização.
  drawFrame() {
    const { ctx } = this;
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    this.drawTable();

    this.particles.forEach((particle) => {
      const { pos: [x, y], radius, color } = particle;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fillStyle = color;
      ctx.fill();
      ctx.strokeStyle = 'black';
      ctx.lineWidth = 1;
      ctx.stroke();
    });
    
    // Controla o que é desenhado com base no estado do taco.
    if (this.cueState.status === 'aiming') {
      this.drawCue();
    } else if (this.cueState.status === 'striking') {
      this.animateAndStrike();
    }

    this.animationFrameId = requestAnimationFrame(() => this.drawFrame());
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

  drawCue(pullbackOverride = null) {
    const { ctx } = this;
    const { start, end } = this.cueState;
    const whiteBall = Array.from(this.particles.values()).find(p => p.color === "white");

    if (!whiteBall) {
      this.cueState.status = 'inactive';
      return;
    }

    const CUE_LENGTH = 450, CUE_BUTT_WIDTH = 16, CUE_TIP_WIDTH = 7, PULLBACK_OFFSET = 10;
    const pullX = end.x - start.x;
    const pullY = end.y - start.y;
    const pullDistance = pullbackOverride !== null ? pullbackOverride : Math.sqrt(pullX * pullX + pullY * pullY);
    
    const dirX = -pullX, dirY = -pullY;
    const dirLen = Math.sqrt(dirX * dirX + dirY * dirY);
    if (dirLen === 0) return;
    const normX = dirX / dirLen, normY = dirY / dirLen;

    if (this.cueState.status === 'aiming') {
        ctx.save();
        ctx.beginPath();
        ctx.moveTo(start.x, start.y);
        ctx.setLineDash([5, 10]);
        ctx.lineTo(start.x + normX * 2000, start.y + normY * 2000);
        ctx.strokeStyle = "rgba(255, 255, 255, 0.6)";
        ctx.lineWidth = 2;
        ctx.stroke();
        ctx.restore();
    }

    const tipX = start.x - normX * (whiteBall.radius + PULLBACK_OFFSET + pullDistance);
    const tipY = start.y - normY * (whiteBall.radius + PULLBACK_OFFSET + pullDistance);
    const buttX = tipX - normX * CUE_LENGTH;
    const buttY = tipY - normY * CUE_LENGTH;
    const perpX = -normY, perpY = normX;

    const p1 = { x: tipX + perpX * CUE_TIP_WIDTH / 2, y: tipY + perpY * CUE_TIP_WIDTH / 2 };
    const p2 = { x: tipX - perpX * CUE_TIP_WIDTH / 2, y: tipY - perpY * CUE_TIP_WIDTH / 2 };
    const p3 = { x: buttX - perpX * CUE_BUTT_WIDTH / 2, y: buttY - perpY * CUE_BUTT_WIDTH / 2 };
    const p4 = { x: buttX + perpX * CUE_BUTT_WIDTH / 2, y: buttY + perpY * CUE_BUTT_WIDTH / 2 };
    
    const gradient = ctx.createLinearGradient(p2.x, p2.y, p4.x, p4.y);
    gradient.addColorStop(0, '#A0522D');
    gradient.addColorStop(0.5, '#D2B48C');
    gradient.addColorStop(1, '#8B4513');
    ctx.fillStyle = gradient;

    ctx.beginPath();
    ctx.moveTo(p1.x, p1.y);
    ctx.lineTo(p2.x, p2.y);
    ctx.lineTo(p3.x, p3.y);
    ctx.lineTo(p4.x, p4.y);
    ctx.closePath();
    ctx.fill();
    ctx.strokeStyle = "rgba(0, 0, 0, 0.4)";
    ctx.lineWidth = 1;
    ctx.stroke();
  },

  // --- Manipuladores de Eventos ---
  handleMouseDown(e) {
    const rect = this.canvas.getBoundingClientRect();
    this.startAiming(e.clientX - rect.left, e.clientY - rect.top);
  },

  handleMouseMove(e) {
    if (this.cueState.status === 'aiming') {
      const rect = this.canvas.getBoundingClientRect();
      this.updateAim(e.clientX - rect.left, e.clientY - rect.top);
    }
  },

  handleMouseUp() {
    this.removeGlobalListeners();
    this.applyStrike();
  },

  handleTouchStart(e) {
    e.preventDefault();
    const touch = e.touches[0];
    const rect = this.canvas.getBoundingClientRect();
    this.startAiming(touch.clientX - rect.left, touch.clientY - rect.top);
  },

  handleTouchMove(e) {
    e.preventDefault();
    if (this.cueState.status === 'aiming') {
      const touch = e.touches[0];
      const rect = this.canvas.getBoundingClientRect();
      this.updateAim(touch.clientX - rect.left, touch.clientY - rect.top);
    }
  },

  handleTouchEnd() {
    this.removeGlobalListeners();
    this.applyStrike();
  },
   
  // --- Lógica de Controle do Taco ---
  startAiming(x, y) {
    if (this.cueState.status !== 'inactive') return;

    const whiteBall = Array.from(this.particles.values()).find(p => p.color === "white");
    if (whiteBall) {
      const [wx, wy] = whiteBall.pos;
      const distance = Math.sqrt((x - wx)**2 + (y - wy)**2);
      if (distance <= whiteBall.radius + 30) {
        this.cueState.status = 'aiming';
        this.cueState.start = { x: wx, y: wy };
        this.cueState.end = { x, y };
        // Adiciona os listeners na janela inteira
        this.addGlobalListeners();
      }
    }
  },

  updateAim(x, y) {
    this.cueState.end = { x, y };
  },

  applyStrike() {
    if (this.cueState.status !== 'aiming') return;
    const { start, end } = this.cueState;
    const dx = start.x - end.x;
    const dy = start.y - end.y;
    this.cueState.status = 'striking';
    this.cueState.animation.startTime = performance.now();
    this.cueState.animation.force = { x: dx * 0.1, y: dy * 0.1 };
    this.cueState.animation.initialPullDistance = Math.sqrt(dx*dx + dy*dy);
  },

  // --- Funções Auxiliares para Listeners Globais ---
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

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
