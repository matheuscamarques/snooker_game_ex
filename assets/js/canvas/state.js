/**
 * Cria o estado inicial para a câmera.
 * @returns {object} O objeto de estado da câmera.
 */
export function createInitialCameraState() {
  return {
    pan: { x: 1000 / 2, y: 500 / 2 }, // Centraliza na mesa
    zoom: 1.0,
    rotation: 0,
    isPanning: false,
    lastMouse: { x: 0, y: 0 },
    lastTouchDistance: 0,
    lastTouchMidpoint: { x: 0, y: 0 },
    panState: { up: false, down: false, left: false, right: false },
    keyboardPanState: { up: false, down: false, left: false, right: false },
    PAN_SPEED: 500
  };
}

/**
 * Cria o estado inicial para o taco de sinuca.
 * @returns {object} O objeto de estado do taco.
 */
export function createInitialCueState() {
  return {
    status: 'inactive', // 'inactive', 'aiming', 'striking'
    start: { x: 0, y: 0 },
    end: { x: 0, y: 0 },
    MAX_PULL_DISTANCE: 200,
    animation: {
      startTime: 0,
      duration: 150, // Duração da animação da tacada em ms
      force: { x: 0, y: 0 },
      initialPullDistance: 0,
    }
  };
}