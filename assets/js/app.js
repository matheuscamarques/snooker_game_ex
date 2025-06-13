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
  // Chamado quando o elemento é adicionado ao DOM
  mounted() {
    this.canvas = this.el.querySelector("#physics-canvas");
    this.ctx = this.canvas.getContext("2d");
    this.particles = new Map();
    this.cue = { active: false, start: null, end: null };

    // --- Configuração dos Eventos ---
    this.canvas.addEventListener("mousedown", this.handleMouseDown.bind(this));
    this.canvas.addEventListener("mousemove", this.handleMouseMove.bind(this));
    this.canvas.addEventListener("mouseup", this.handleMouseUp.bind(this));

    // Recebe atualizações de posição das partículas do servidor
    this.handleEvent("particle_moved", (payload) => {
      this.particles.set(payload.id, payload);
    });

    // --- Início do Loop de Animação ---
    // Inicia o loop que irá redesenhar o canvas continuamente
    this.animationFrameId = requestAnimationFrame(() => this.drawFrame());
  },

  // Chamado quando o elemento é removido do DOM
  destroyed() {
    // CORREÇÃO: Cancela o loop de animação para evitar processamento
    // desnecessário e vazamentos de memória quando o usuário sai da página.
    if (this.animationFrameId) {
      cancelAnimationFrame(this.animationFrameId);
    }
  },

  // Desenha a mesa de sinuca (fundo estático)
  drawTable() {
    const { ctx, canvas } = this;
    
    // Fundo verde (tecido)
    ctx.fillStyle = "#1a6d38";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    
    // Bordas da mesa
    ctx.fillStyle = "#8B4513"; // Cor de madeira
    const borderWidth = 30;
    ctx.fillRect(0, 0, canvas.width, borderWidth);                   // Topo
    ctx.fillRect(0, canvas.height - borderWidth, canvas.width, borderWidth);  // Base
    ctx.fillRect(0, 0, borderWidth, canvas.height);                  // Esquerda
    ctx.fillRect(canvas.width - borderWidth, 0, borderWidth, canvas.height);  // Direita
    
    // Caçapas
    ctx.fillStyle = "black";
    const pocketRadius = 25;
    const pockets = [
      [borderWidth, borderWidth],
      [canvas.width - borderWidth, borderWidth],
      [borderWidth, canvas.height - borderWidth],
      [canvas.width - borderWidth, canvas.height - borderWidth],
      [borderWidth, canvas.height / 2],
      [canvas.width - borderWidth, canvas.height / 2]
    ];
    
    pockets.forEach(([x, y]) => {
      ctx.beginPath();
      ctx.arc(x, y, pocketRadius, 0, Math.PI * 2);
      ctx.fill();
    });
  },

  // Função principal de renderização, chamada a cada quadro
  drawFrame() {
    const { ctx } = this;

    // --- Limpeza e Fundo ---
    // CORREÇÃO: Limpa o canvas inteiramente antes de desenhar o novo quadro.
    // Isso é essencial para a animação, evitando "rastros" das bolas.
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    
    // CORREÇÃO: Redesenha a mesa a cada quadro para servir de fundo limpo.
    this.drawTable();
    
    // --- Desenho dos Elementos Dinâmicos ---
    // Desenha as bolas
    this.particles.forEach((particle) => {
      const { pos: [x, y], radius, color } = particle;
      
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fillStyle = color;
      ctx.fill();
      
      // Adiciona uma borda para melhor visualização
      ctx.strokeStyle = 'black';
      ctx.lineWidth = 1;
      ctx.stroke();
    });
    
    // Desenha o taco quando o jogador estiver mirando
    if (this.cue.active) {
      const { start, end } = this.cue;
      ctx.beginPath();
      ctx.moveTo(start.x, start.y);
      ctx.lineTo(end.x, end.y);
      ctx.strokeStyle = "rgba(255, 255, 224, 0.8)"; // Cor de marfim claro
      ctx.lineWidth = 4;
      ctx.stroke();
    }
    
    // Agenda a próxima chamada para esta função, criando o loop
    this.animationFrameId = requestAnimationFrame(() => this.drawFrame());
  },

  // --- Manipuladores de Eventos do Mouse ---
  handleMouseDown(e) {
    const rect = this.canvas.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    
    // Encontra a bola branca no Map de partículas
    const whiteBall = Array.from(this.particles.values()).find(p => p.color === "white");
    
    if (whiteBall) {
      const [wx, wy] = whiteBall.pos;
      const distance = Math.sqrt((x - wx)**2 + (y - wy)**2);
      
      // Permite iniciar a mira apenas se o clique for perto da bola branca
      if (distance <= whiteBall.radius + 5) { // Adiciona uma pequena tolerância
        this.cue = {
          active: true,
          start: { x: wx, y: wy },
          end: { x, y }
        };
      }
    }
  },

  handleMouseMove(e) {
    if (this.cue.active) {
      const rect = this.canvas.getBoundingClientRect();
      this.cue.end = {
        x: e.clientX - rect.left,
        y: e.clientY - rect.top
      };
    }
  },

  handleMouseUp() {
    if (this.cue.active) {
      // Calcula o vetor de força baseado na distância e direção do arrasto do mouse
      const dx = this.cue.start.x - this.cue.end.x;
      const dy = this.cue.start.y - this.cue.end.y;
      
      // O fator de multiplicação (0.1) controla a sensibilidade da força
      const force = { x: dx * 0.1, y: dy * 0.1 };
      
      // Envia o evento de "tacada" para o servidor
      this.pushEvent("apply_force", force);
      
      // Desativa a mira
      this.cue.active = false;
    }
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

