/**
 * @file state.js
 * @description Define os estados iniciais para os componentes do canvas.
 */

// Estado inicial para a câmera
export function createInitialCameraState() {
  return {
    pan: { x: 0, y: 0 },
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

// Estado inicial para o taco de sinuca
export function createInitialCueState() {
  return {
    status: 'inactive', // 'inactive', 'aiming', 'striking'
    start: { x: 0, y: 0 },
    end: { x: 0, y: 0 },
    MAX_PULL_DISTANCE: 200,
    animation: {
      startTime: 0,
      duration: 150,
      force: { x: 0, y: 0 },
      initialPullDistance: 0,
    }
  };
}
