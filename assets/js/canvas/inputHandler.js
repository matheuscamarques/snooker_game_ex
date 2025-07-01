class InputHandler {
    constructor(hook) {
        this.hook = hook;
        
        // --- CORREÇÃO: Encontra os elementos da UI no hook.el ---
        this.startScreen = this.hook.el.querySelector("#start-screen");
        this.gameContainer = this.hook.el.querySelector(".game-container");
        this.startGameBtn = this.hook.el.querySelector("#start-game-btn");

        this.bindAllMethods();
    }

    bindAllMethods() {
        // --- CORREÇÃO: Adiciona o handler para o clique inicial ---
        this.handleStartClick = this.handleStartClick.bind(this);
        
        this.handleMouseDown = this.handleMouseDown.bind(this);
        this.handleMouseMove = this.handleMouseMove.bind(this);
        this.handleMouseUp = this.handleMouseUp.bind(this);
        this.handleWheel = this.handleWheel.bind(this);
        this.handleTouchStart = this.handleTouchStart.bind(this);
        this.handleTouchMove = this.handleTouchMove.bind(this);
        this.handleTouchEnd = this.handleTouchEnd.bind(this);
        this.handleKeyDown = this.handleKeyDown.bind(this);
        this.handleKeyUp = this.handleKeyUp.bind(this);
        this.resizeCanvas = this.resizeCanvas.bind(this);
    }

    // --- CORREÇÃO: Novo método para orquestrar o início ---
    handleStartClick() {
        if (!this.startScreen || !this.gameContainer) return;

        console.log("Botão de início clicado. Transicionando UI...");

        // 1. Esconde a tela de início
        this.startScreen.style.display = 'none';

        // 2. Mostra o contêiner do jogo usando a classe do CSS
        this.gameContainer.classList.add('visible');

        // 3. Diz ao hook para iniciar a lógica do jogo (pedir dados, desenhar)
        // O setTimeout dá ao navegador um instante para aplicar as mudanças de CSS
        setTimeout(() => {
            this.hook.startGame();
        }, 50);
    }

    addEventListeners() {
        // --- CORREÇÃO: Listener no botão de início ---
        this.startGameBtn?.addEventListener('click', this.handleStartClick);

        // O resto dos listeners permanece o mesmo
        this.hook.canvas.addEventListener("mousedown", this.handleMouseDown);
        this.hook.canvas.addEventListener("touchstart", this.handleTouchStart, { passive: false });
        this.hook.canvas.addEventListener("wheel", this.handleWheel, { passive: false });
        this.hook.canvas.addEventListener('contextmenu', e => e.preventDefault());
        
        this.hook.el.querySelector("#rotate-btn")?.addEventListener("click", () => this.hook.cameraModule.rotateCamera(this.hook.camera));
        this.hook.el.querySelector("#zoom-in-btn")?.addEventListener("click", () => this.hook.cameraModule.zoom(this.hook.camera, 1.2, null, this.hook.canvas));
        this.hook.el.querySelector("#zoom-out-btn")?.addEventListener("click", () => this.hook.cameraModule.zoom(this.hook.camera, 0.8, null, this.hook.canvas));
        this.hook.el.querySelector("#reset-view-btn")?.addEventListener("click", () => this.hook.cameraModule.resetView(this.hook.camera));
        this.setupDPadListeners();
        
        window.addEventListener('resize', this.resizeCanvas);
        window.addEventListener('keydown', this.handleKeyDown);
        window.addEventListener('keyup', this.handleKeyUp);
    }

    removeEventListeners() {
        this.startGameBtn?.removeEventListener('click', this.handleStartClick);
        window.removeEventListener('resize', this.resizeCanvas);
        window.removeEventListener('keydown', this.handleKeyDown);
        window.removeEventListener('keyup', this.handleKeyUp);
        this.removeGlobalListeners();
    }
    
    resizeCanvas() { 
        if (!this.hook.canvasWrapper) return;
        const rect = this.hook.canvasWrapper.getBoundingClientRect(); 
        if (this.hook.canvas.width !== rect.width || this.hook.canvas.height !== rect.height) {
            this.hook.canvas.width = rect.width; 
            this.hook.canvas.height = rect.height; 
        }
    }

    // O resto do arquivo (handleMouseDown, etc.) pode permanecer como está.
    handleMouseDown(e) { e.preventDefault(); const mousePos = this.getMousePos(e); if (e.button === 0) { const worldPos = this.hook.cameraModule.screenToWorld(mousePos, this.hook.camera, this.hook.canvas); this.hook.cueModule.startAiming(this.hook, worldPos); } else if (e.button === 2) { this.hook.camera.isPanning = true; this.hook.camera.lastMouse = mousePos; this.hook.canvas.style.cursor = 'grabbing'; this.addGlobalListeners(); } }
    handleMouseMove(e) { const mousePos = this.getMousePos(e); if (this.hook.camera.isPanning) { const { camera } = this.hook; const cosR = Math.cos(camera.rotation), sinR = Math.sin(camera.rotation); const dx = (mousePos.x - camera.lastMouse.x) / camera.zoom; const dy = (mousePos.y - camera.lastMouse.y) / camera.zoom; camera.pan.x -= dx * cosR + dy * sinR; camera.pan.y -= dy * cosR - dx * sinR; camera.lastMouse = mousePos; } else if (this.hook.cueState.status === 'aiming') { const worldPos = this.hook.cameraModule.screenToWorld(mousePos, this.hook.camera, this.hook.canvas); this.hook.cueModule.updateAim(this.hook.cueState, worldPos); } }
    handleMouseUp(e) { if (e.button === 2) { this.hook.camera.isPanning = false; this.hook.canvas.style.cursor = 'grab'; } if (this.hook.cueState.status === 'aiming' && e.button === 0) { this.hook.cueModule.applyStrike(this.hook); } this.removeGlobalListeners(); }
    handleWheel(e) { e.preventDefault(); const zoomFactor = e.deltaY < 0 ? 1.1 : 0.9; this.hook.cameraModule.zoom(this.hook.camera, zoomFactor, this.getMousePos(e), this.hook.canvas); }
    handleTouchStart(e) { e.preventDefault(); if (e.touches.length === 1) { const worldPos = this.hook.cameraModule.screenToWorld(this.getMousePos(e.touches[0]), this.hook.camera, this.hook.canvas); this.hook.cueModule.startAiming(this.hook, worldPos); } else if (e.touches.length === 2) { this.hook.cueState.status = 'inactive'; this.hook.camera.isPanning = true; this.hook.camera.lastTouchDistance = this.getTouchDistance(e.touches); this.hook.camera.lastTouchMidpoint = this.getTouchMidpoint(e.touches); this.addGlobalListeners(); } }
    handleTouchMove(e) { e.preventDefault(); const { camera, cueState } = this.hook; if (cueState.status === 'aiming' && e.touches.length === 1) { const worldPos = this.hook.cameraModule.screenToWorld(this.getMousePos(e.touches[0]), camera, this.hook.canvas); this.hook.cueModule.updateAim(cueState, worldPos); } else if (camera.isPanning && e.touches.length === 2) { const newMidpoint = this.getTouchMidpoint(e.touches); const newDistance = this.getTouchDistance(e.touches); if (camera.lastTouchDistance > 0) { const zoomFactor = newDistance / camera.lastTouchDistance; this.hook.cameraModule.zoom(camera, zoomFactor, newMidpoint, this.hook.canvas); } const cosR = Math.cos(camera.rotation), sinR = Math.sin(camera.rotation); const dx = (newMidpoint.x - camera.lastTouchMidpoint.x) / camera.zoom; const dy = (newMidpoint.y - camera.lastTouchMidpoint.y) / camera.zoom; camera.pan.x -= dx * cosR + dy * sinR; camera.pan.y -= dy * cosR - dx * sinR; camera.lastTouchDistance = newDistance; camera.lastTouchMidpoint = newMidpoint; } }
    handleTouchEnd(e) { if (e.touches.length < 2) this.hook.camera.isPanning = false; if (e.touches.length < 1 && this.hook.cueState.status === 'aiming') { this.hook.cueModule.applyStrike(this.hook); } this.removeGlobalListeners(); }
    handleKeyDown(e) { const keyMap = { "ArrowUp": "up", "KeyW": "up", "ArrowDown": "down", "KeyS": "down", "ArrowLeft": "left", "KeyA": "left", "ArrowRight": "right", "KeyD": "right" }; if (keyMap[e.code]) { e.preventDefault(); this.hook.camera.keyboardPanState[keyMap[e.code]] = true; } }
    handleKeyUp(e) { const keyMap = { "ArrowUp": "up", "KeyW": "up", "ArrowDown": "down", "KeyS": "down", "ArrowLeft": "left", "KeyA": "left", "ArrowRight": "right", "KeyD": "right" }; if (keyMap[e.code]) { e.preventDefault(); this.hook.camera.keyboardPanState[keyMap[e.code]] = false; } }
    getMousePos(e) { const rect = this.hook.canvas.getBoundingClientRect(); return { x: e.clientX - rect.left, y: e.clientY - rect.top }; }
    getTouchDistance(touches) { const dx = touches[0].clientX - touches[1].clientX; const dy = touches[0].clientY - touches[1].clientY; return Math.sqrt(dx * dx + dy * dy); }
    getTouchMidpoint(touches) { const rect = this.hook.canvas.getBoundingClientRect(); const x = (touches[0].clientX + touches[1].clientX) / 2 - rect.left; const y = (touches[0].clientY + touches[1].clientY) / 2 - rect.top; return { x, y }; }
    addGlobalListeners() { window.addEventListener("mousemove", this.handleMouseMove); window.addEventListener("mouseup", this.handleMouseUp); window.addEventListener("touchmove", this.handleTouchMove, { passive: false }); window.addEventListener("touchend", this.handleTouchEnd, { passive: false }); }
    removeGlobalListeners() { window.removeEventListener("mousemove", this.handleMouseMove); window.removeEventListener("mouseup", this.handleMouseUp); window.removeEventListener("touchmove", this.handleTouchMove); window.removeEventListener("touchend", this.handleTouchEnd); }
    setupDPadListeners() { const dPadMap = { "d-pad-up": "up", "d-pad-down": "down", "d-pad-left": "left", "d-pad-right": "right" }; for (const [id, direction] of Object.entries(dPadMap)) { const button = this.hook.el.querySelector(`#${id}`); if(button) { const setPanState = (state) => { this.hook.camera.panState[direction] = state; }; button.addEventListener("mousedown", () => setPanState(true)); button.addEventListener("touchstart", (e) => { e.preventDefault(); setPanState(true); }); button.addEventListener("mouseup", () => setPanState(false)); button.addEventListener("touchend", (e) => { e.preventDefault(); setPanState(false); }); button.addEventListener("mouseleave", () => setPanState(false)); } } }
}

export default InputHandler;
