/**
 * @file camera.js
 * @description Funções para controlar a câmera do canvas (pan, zoom, rotação).
 */

/** Converte coordenadas da tela para o mundo do canvas */
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

/** Reseta a visão da câmera para a posição inicial */
export function resetView(camera) {
  camera.pan = { x: 1000 / 2, y: 500 / 2 }; // Assumindo tamanho do mundo
  camera.zoom = 1.0;
  camera.rotation = 0;
}

/** Rotaciona a câmera em 90 graus */
export function rotateCamera(camera) {
  camera.rotation += Math.PI / 2;
}

/** Aplica zoom na câmera */
export function zoom(camera, factor, zoomCenter, canvas) {
  const center = zoomCenter || { x: canvas.width / 2, y: canvas.height / 2 };
  const worldPosBeforeZoom = screenToWorld(center, camera, canvas);
  
  camera.zoom *= factor;

  const worldPosAfterZoom = screenToWorld(center, camera, canvas);
  camera.pan.x += worldPosBeforeZoom.x - worldPosAfterZoom.x;
  camera.pan.y += worldPosBeforeZoom.y - worldPosAfterZoom.y;
}

/** Atualiza a posição do pan com base no estado (teclado ou D-pad) */
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
