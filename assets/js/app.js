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
  // Called when the hook is mounted to a DOM element.
  mounted() {
    this.canvas = this.el.querySelector("#physics-canvas");
    this.ctx = this.canvas.getContext("2d");
    this.particles = new Map();
    this.cue = { active: false, start: null, end: null };

    // --- Event Listener Setup ---
    this.canvas.addEventListener("mousedown", this.handleMouseDown.bind(this));
    this.canvas.addEventListener("mousemove", this.handleMouseMove.bind(this));
    this.canvas.addEventListener("mouseup", this.handleMouseUp.bind(this));

    // Listens for position updates from the server.
    this.handleEvent("particle_moved", (payload) => {
      // Stores the latest state of each particle in a Map for fast lookups.
      this.particles.set(payload.id, payload);
    });

    // --- Animation Loop Start ---
    // Kicks off the continuous rendering loop.
    this.animationFrameId = requestAnimationFrame(() => this.drawFrame());
  },

  // Called when the DOM element is removed.
  destroyed() {
    // Cancels the animation loop to prevent unnecessary processing and
    // memory leaks when the user navigates away.
    if (this.animationFrameId) {
      cancelAnimationFrame(this.animationFrameId);
    }
  },

  // Draws the static snooker table background.
  drawTable() {
    const { ctx, canvas } = this;

    // Green felt background
    ctx.fillStyle = "#1a6d38";
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    // Wooden borders
    ctx.fillStyle = "#8B4513";
    const borderWidth = 30;
    ctx.fillRect(0, 0, canvas.width, borderWidth);                   // Top
    ctx.fillRect(0, canvas.height - borderWidth, canvas.width, borderWidth);  // Bottom
    ctx.fillRect(0, 0, borderWidth, canvas.height);                  // Left
    ctx.fillRect(canvas.width - borderWidth, 0, borderWidth, canvas.height);  // Right

    // Pockets
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

  // The main rendering function, called on every animation frame.
  drawFrame() {
    const { ctx } = this;

    // --- Clear and Redraw Background ---
    // Clears the entire canvas before drawing the new frame.
    // This is essential for animation to avoid "ghosting" trails.
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

    // Redraw the table every frame to serve as a clean background.
    this.drawTable();

    // --- Draw Dynamic Elements ---
    // Draw all the balls.
    this.particles.forEach((particle) => {
      const { pos: [x, y], radius, color } = particle;

      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fillStyle = color;
      ctx.fill();

      // Add a border for better visibility.
      ctx.strokeStyle = 'black';
      ctx.lineWidth = 1;
      ctx.stroke();
    });

    // Draw the cue stick if the player is aiming.
    if (this.cue.active) {
      const { start, end } = this.cue;
      ctx.beginPath();
      ctx.moveTo(start.x, start.y);
      ctx.lineTo(end.x, end.y);
      ctx.strokeStyle = "rgba(255, 255, 224, 0.8)"; // Light ivory color
      ctx.lineWidth = 4;
      ctx.stroke();
    }

    // Schedule the next call to this function, creating the loop.
    this.animationFrameId = requestAnimationFrame(() => this.drawFrame());
  },

  // --- Mouse Event Handlers ---
  handleMouseDown(e) {
    const rect = this.canvas.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    // Find the white ball in the particle Map.
    const whiteBall = Array.from(this.particles.values()).find(p => p.color === "white");

    if (whiteBall) {
      const [wx, wy] = whiteBall.pos;
      const distance = Math.sqrt((x - wx)**2 + (y - wy)**2);

      // Only allow aiming to start if the click is near the white ball.
      if (distance <= whiteBall.radius + 5) { // Add a small tolerance
        this.cue = {
          active: true,
          start: { x: wx, y: wy },
          end: { x, y }
        };
      }
    }
  },

  handleMouseMove(e) {
    // If aiming is active, update the end position of the cue.
    if (this.cue.active) {
      const rect = this.canvas.getBoundingClientRect();
      this.cue.end = {
        x: e.clientX - rect.left,
        y: e.clientY - rect.top
      };
    }
  },

  handleMouseUp() {
    // When the mouse button is released, finalize the shot.
    if (this.cue.active) {
      // Calculate the force vector based on the mouse drag distance and direction.
      const dx = this.cue.start.x - this.cue.end.x;
      const dy = this.cue.start.y - this.cue.end.y;

      // The multiplication factor (0.1) controls the force sensitivity.
      const force = { x: dx * 0.1, y: dy * 0.1 };

      // Send the "strike" event to the server.
      this.pushEvent("apply_force", force);

      // Deactivate aiming.
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
