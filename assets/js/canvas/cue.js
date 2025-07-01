/**
 * @file cue.js
 * @description Lógica para o taco de sinuca, incluindo mira e tacada.
 */

function getPullDistance(cueState) {
    const { start, end } = cueState;
    const dx = end.x - start.x;
    const dy = end.y - start.y;
    return Math.sqrt(dx * dx + dy * dy);
}

/** Inicia o processo de mira */
export function startAiming(hook, worldPos) {
    if (hook.cueState.status !== 'inactive' || hook.camera.isPanning) return;

    const whiteBall = Array.from(hook.particles.values()).find(p => p.color.type === "cue");
    if (whiteBall) {
        const [wx, wy] = whiteBall.pos;
        const distance = Math.sqrt((worldPos.x - wx)**2 + (worldPos.y - wy)**2);

        if (distance <= whiteBall.radius + 30 / hook.camera.zoom) {
            hook.pushEvent("hold_ball", {});
            hook.cueState.status = 'aiming';
            hook.cueState.start = { x: wx, y: wy };
            hook.cueState.end = worldPos;
            hook.inputHandler.addGlobalListeners();
        }
    }
}

/** Atualiza a posição da mira */
export function updateAim(cueState, worldPos) {
    cueState.end = worldPos;
}

/** Calcula a força e inicia a animação da tacada */
export function applyStrike(hook) {
    if (hook.cueState.status !== 'aiming') return;

    const { start, end } = hook.cueState;
    const pullDistance = getPullDistance(hook.cueState);
    const power = Math.min(pullDistance / hook.cueState.MAX_PULL_DISTANCE, 1);

    const dx = start.x - end.x;
    const dy = start.y - end.y;
    const dirLen = Math.sqrt(dx * dx + dy * dy);

    if (dirLen === 0) {
        hook.cueState.status = 'inactive';
        return;
    }

    const normX = dx / dirLen;
    const normY = dy / dirLen;
    const forceMultiplier = 1000 * power;

    hook.cueState.status = 'striking';
    hook.cueState.animation.startTime = performance.now();
    hook.cueState.animation.force = { x: normX * forceMultiplier, y: normY * forceMultiplier };
    hook.cueState.animation.initialPullDistance = pullDistance;
}
