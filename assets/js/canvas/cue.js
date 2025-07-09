/**
 * @file cue.js
 * @description Lógica para o taco de sinuca, incluindo mira e tacada.
 */

/** Calcula a distância que o taco foi puxado para trás. */
function getPullDistance(cueState) {
    const { start, end } = cueState;
    const dx = end.x - start.x;
    const dy = end.y - start.y;
    return Math.sqrt(dx * dx + dy * dy);
}

/**
 * Inicia o processo de mira quando o jogador clica perto da bola branca.
 * @param {object} hook - A instância do LiveView Hook.
 * @param {object} worldPos - A posição do clique no mundo do jogo.
 */
export function startAiming(hook, worldPos) {
    // Impede a mira se o jogo estiver no estado "não pode atirar".
    if (hook.el.dataset.canShoot === 'false') {
        console.warn("Não é possível mirar: aguarde o fim da jogada.");
        return;
    }

    if (hook.cueState.status !== 'inactive' || hook.camera.isPanning) return;

    const whiteBall = Array.from(hook.particles.values()).find(p => p.color.type === "cue");
    if (whiteBall) {
        const [wx, wy] = whiteBall.pos;
        const distance = Math.sqrt((worldPos.x - wx)**2 + (worldPos.y - wy)**2);

        // Permite iniciar a mira se o clique for perto da bola branca
        if (distance <= whiteBall.radius + 30 / hook.camera.zoom) {
            // A chamada a `pushEvent("hold_ball", ...)` foi permanentemente removida daqui.
            // Este era o ponto que causava o erro.
            
            hook.cueState.status = 'aiming';
            hook.cueState.start = { x: wx, y: wy };
            hook.cueState.end = worldPos;
            hook.inputHandler.addGlobalListeners();
        }
    }
}

/**
 * Atualiza a posição da mira enquanto o jogador move o rato/dedo.
 * @param {object} cueState - O estado do taco.
 * @param {object} worldPos - A nova posição do cursor no mundo.
 */
export function updateAim(cueState, worldPos) {
    cueState.end = worldPos;
}

/**
 * Finaliza a mira, calcula a força e inicia a animação da tacada.
 * @param {object} hook - A instância do LiveView Hook.
 */
export function applyStrike(hook) {
    if (hook.cueState.status !== 'aiming') return;

    const { start, end } = hook.cueState;
    const pullDistance = getPullDistance(hook.cueState);
    const power = Math.min(pullDistance / hook.cueState.MAX_PULL_DISTANCE, 1);

    const dx = start.x - end.x;
    const dy = start.y - end.y;
    const dirLen = Math.sqrt(dx * dx + dy * dy);

    if (dirLen < 5) { // Se o puxão for muito pequeno, cancela a tacada
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
