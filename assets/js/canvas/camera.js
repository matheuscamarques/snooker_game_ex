/** * Converte coordenadas da tela (evento do rato/toque) para coordenadas do mundo do canvas.
 * @param {object} screenPos - A posição na tela { x, y }.
 * @param {object} camera - O estado atual da câmera.
 * @param {HTMLCanvasElement} canvas - O elemento canvas.
 * @returns {object} A posição no mundo { x, y }.
 */
export function screenToWorld({ x, y }, camera, canvas) {
  const { pan, zoom, rotation } = camera;
  const { width, height } = canvas;
  const relX = x - width / 2;
  const relY = y - height / 2;
  const unscaledX = relX / zoom;
  const unscaledY = relY / zoom;
  const cosR = Math.cos(-rotation);
  const sinR = Math.sin(-rotation);
  const rotatedX = unscaledX * cosR - unscaledY * sinR;
  const rotatedY = unscaledX * sinR + unscaledY * cosR;
  return { x: rotatedX + pan.x, y: rotatedY + pan.y };
}

/** Reseta a visão da câmera para a posição e zoom iniciais. */
export function resetView(camera) {
  camera.pan = { x: 1000 / 2, y: 500 / 2 };
  camera.zoom = 1.0;
  camera.rotation = 0;
}

/** Rotaciona a câmera em 90 graus no sentido horário. */
export function rotateCamera(camera) {
  camera.rotation += Math.PI / 2;
}

/** * Aplica zoom na câmera, mantendo o ponto sob o cursor fixo.
 * @param {object} camera - O estado da câmera.
 * @param {number} factor - O fator de zoom (ex: 1.1 para aumentar, 0.9 para diminuir).
 * @param {object} zoomCenter - A posição na tela onde o zoom é centrado.
 * @param {HTMLCanvasElement} canvas - O elemento canvas.
 */
export function zoom(camera, factor, zoomCenter, canvas) {
  const center = zoomCenter || { x: canvas.width / 2, y: canvas.height / 2 };
  const worldPosBeforeZoom = screenToWorld(center, camera, canvas);
  
  camera.zoom *= factor;
  camera.zoom = Math.max(0.5, Math.min(camera.zoom, 4)); // Limita o zoom

  const worldPosAfterZoom = screenToWorld(center, camera, canvas);
  camera.pan.x += worldPosBeforeZoom.x - worldPosAfterZoom.x;
  camera.pan.y += worldPosBeforeZoom.y - worldPosAfterZoom.y;
}

/** * Atualiza a posição do pan (movimento lateral) com base no estado dos controlos.
 * @param {object} camera - O estado da câmera.
 * @param {object} state - O estado do pan (teclado ou D-pad).
 * @param {number} deltaTime - O tempo decorrido desde o último frame.
 */
export function updatePan(camera, state, deltaTime) {
  const { zoom, rotation, PAN_SPEED } = camera;
  const moveAmount = (PAN_SPEED * deltaTime) / zoom;
  let moveX = 0, moveY = 0;

  if (state.up) moveY -= moveAmount;
  if (state.down) moveY += moveAmount;
  if (state.left) moveX -= moveAmount;
  if (state.right) moveX += moveAmount;

  if (moveX === 0 && moveY === 0) return;

  const cosR = Math.cos(rotation);
  const sinR = Math.sin(rotation);
  camera.pan.x += moveX * cosR - moveY * sinR;
  camera.pan.y += moveX * sinR + moveY * cosR;
}

