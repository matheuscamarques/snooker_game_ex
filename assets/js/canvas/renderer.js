/**
 * @file renderer.js
 * @description Contém todas as funções para desenhar no canvas.
 */

// Função principal de desenho, chamada a cada frame
export function drawFrame(hook) {
    const now = performance.now();
    const deltaTime = (now - hook.lastFrameTime) / 1000;
    hook.lastFrameTime = now;

    // Atualiza a câmera com base nos inputs
    hook.cameraModule.updatePan(hook.camera, hook.camera.panState, deltaTime);
    hook.cameraModule.updatePan(hook.camera, hook.camera.keyboardPanState, deltaTime);

    const { ctx, canvas, camera, particles, cueState } = hook;
    const { width, height } = canvas;
    const { pan, zoom, rotation } = camera;

    ctx.clearRect(0, 0, width, height);
    ctx.save();
    ctx.translate(width / 2, height / 2);
    ctx.rotate(rotation);
    ctx.scale(zoom, zoom);
    ctx.translate(-pan.x, -pan.y);

    drawTable(ctx, 1000, 500); // Desenha a mesa
    particles.forEach((particle) => drawBall(hook, particle)); // Desenha as bolas

    // Lógica de desenho do taco e da barra de força
    if (cueState.status === 'aiming') {
        const pullDistance = Math.sqrt((cueState.end.x - cueState.start.x)**2 + (cueState.end.y - cueState.start.y)**2);
        drawCue(hook, pullDistance);
        updatePowerBar(hook, pullDistance);
    } else if (cueState.status === 'striking') {
        animateAndStrike(hook);
    } else {
        updatePowerBar(hook, 0);
    }
    
    ctx.restore();
    hook.animationFrameId = requestAnimationFrame(() => drawFrame(hook));
}

// --- Funções de Desenho Auxiliares ---

function drawTable(ctx, worldWidth, worldHeight) {
    ctx.fillStyle = "#1a6d38";
    ctx.fillRect(0, 0, worldWidth, worldHeight);
    ctx.fillStyle = "#8B4513";
    const borderWidth = 30;
    ctx.fillRect(0, 0, worldWidth, borderWidth);
    ctx.fillRect(0, worldHeight - borderWidth, worldWidth, borderWidth);
    ctx.fillRect(0, 0, borderWidth, worldHeight);
    ctx.fillRect(worldWidth - borderWidth, 0, borderWidth, worldHeight);
    
    ctx.fillStyle = "black";
    const pocketRadius = 25;
    const pockets = [
      [borderWidth, borderWidth], [worldWidth - borderWidth, borderWidth],
      [borderWidth, worldHeight - borderWidth], [worldWidth - borderWidth, worldHeight - borderWidth],
      [worldWidth / 2, borderWidth], [worldWidth / 2, worldHeight - borderWidth]
    ];
    pockets.forEach(([x, y]) => {
      ctx.beginPath();
      ctx.arc(x, y, pocketRadius, 0, Math.PI * 2);
      ctx.fill();
    });
}

function drawBall(hook, particle) {
    const { ctx, camera } = hook;
    const { pos: [x, y], vel: [vx, vy], radius, color, spin_angle, roll_distance } = particle;
    const { number, type, base_color } = color;

    const speed = Math.sqrt(vx * vx + vy * vy);
    let rollAngle, textureOffsetY;

    if (speed > 0.1) {
        rollAngle = Math.atan2(vy, vx) - Math.PI / 2;
        textureOffsetY = roll_distance % (Math.PI * 2 * radius);
        particle.lastRollAngle = rollAngle;
        particle.lastTextureOffsetY = textureOffsetY;
    } else {
        rollAngle = particle.lastRollAngle || 0;
        textureOffsetY = particle.lastTextureOffsetY || 0;
    }

    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(rollAngle);
    ctx.rotate(spin_angle);

    ctx.beginPath();
    ctx.arc(0, 0, radius, 0, Math.PI * 2);
    ctx.fillStyle = base_color;
    ctx.fill();

    ctx.save();
    ctx.beginPath();
    ctx.arc(0, 0, radius, 0, Math.PI * 2);
    ctx.clip();
    
    const circumference = Math.PI * 2 * radius;

    if (type === 'stripe') {
        const bandHeight = radius * 1.4;
        ctx.fillStyle = 'white';
        ctx.fillRect(-radius, -bandHeight / 2 + textureOffsetY, radius * 2, bandHeight);
        ctx.fillRect(-radius, -bandHeight / 2 + textureOffsetY - circumference, radius * 2, bandHeight);
        ctx.fillRect(-radius, -bandHeight / 2 + textureOffsetY + circumference, radius * 2, bandHeight);
    }

    if (number > 0) {
        const numCircleRadius = radius * 0.6;
        ctx.fillStyle = 'white';
        for (let i = -1; i <= 1; i++) {
            ctx.beginPath();
            ctx.arc(0, textureOffsetY + i * circumference, numCircleRadius, 0, Math.PI * 2);
            ctx.fill();
        }
        
        ctx.fillStyle = 'black';
        ctx.font = `bold ${radius * 0.95}px Arial`;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        for (let i = -1; i <= 1; i++) {
            ctx.fillText(number.toString(), 0, textureOffsetY + i * circumference);
        }
    }
    ctx.restore();
    ctx.restore();

    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    const gradient = ctx.createRadialGradient(x - radius * 0.3, y - radius * 0.3, radius * 0.1, x, y, radius);
    gradient.addColorStop(0, 'rgba(255, 255, 255, 0.7)');
    gradient.addColorStop(0.5, 'rgba(255, 255, 255, 0)');
    gradient.addColorStop(1, 'rgba(0, 0, 0, 0.3)');
    ctx.fillStyle = gradient;
    ctx.fill();

    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    ctx.strokeStyle = 'rgba(0, 0, 0, 0.2)';
    ctx.lineWidth = 1 / camera.zoom;
    ctx.stroke();
}

function drawCue(hook, pullback) {
    const { ctx, cueState, particles, camera } = hook;
    const { start, end } = cueState;
    const whiteBall = Array.from(particles.values()).find(p => p.color.type === "cue");
    if (!whiteBall) { cueState.status = 'inactive'; return; }

    const CUE_LENGTH = 450, CUE_BUTT_WIDTH = 16, CUE_TIP_WIDTH = 7, PULLBACK_OFFSET = 10;
    
    const forceDirX = start.x - end.x;
    const forceDirY = start.y - end.y;
    
    const dirLen = Math.sqrt(forceDirX * forceDirX + forceDirY * forceDirY);
    if (dirLen === 0) return;
    
    const forceNormX = forceDirX / dirLen;
    const forceNormY = forceDirY / dirLen;

    ctx.save();
    ctx.beginPath();
    ctx.moveTo(start.x, start.y);
    ctx.setLineDash([5 / camera.zoom, 10 / camera.zoom]);
    ctx.lineTo(start.x + forceNormX * 2000, start.y + forceNormY * 2000);
    ctx.strokeStyle = "rgba(255, 255, 255, 0.6)";
    ctx.lineWidth = 2 / camera.zoom;
    ctx.stroke();
    ctx.restore();

    const tipX = start.x - forceNormX * (whiteBall.radius + PULLBACK_OFFSET + pullback);
    const tipY = start.y - forceNormY * (whiteBall.radius + PULLBACK_OFFSET + pullback);
    
    const buttX = tipX - forceNormX * CUE_LENGTH;
    const buttY = tipY - forceNormY * CUE_LENGTH;
    
    const perpX = -forceNormY;
    const perpY = forceNormX;
    
    const p1 = { x: tipX + perpX * CUE_TIP_WIDTH / 2, y: tipY + perpY * CUE_TIP_WIDTH / 2 };
    const p2 = { x: tipX - perpX * CUE_TIP_WIDTH / 2, y: tipY - perpY * CUE_TIP_WIDTH / 2 };
    const p3 = { x: buttX - perpX * CUE_BUTT_WIDTH / 2, y: buttY - perpY * CUE_BUTT_WIDTH / 2 };
    const p4 = { x: buttX + perpX * CUE_BUTT_WIDTH / 2, y: buttY + perpY * CUE_BUTT_WIDTH / 2 };
    
    const gradient = ctx.createLinearGradient(p2.x, p2.y, p4.x, p4.y);
    gradient.addColorStop(0, '#A0522D'); gradient.addColorStop(0.5, '#D2B48C'); gradient.addColorStop(1, '#8B4513');
    ctx.fillStyle = gradient;
    ctx.beginPath(); ctx.moveTo(p1.x, p1.y); ctx.lineTo(p2.x, p2.y); ctx.lineTo(p3.x, p3.y); ctx.lineTo(p4.x, p4.y); ctx.closePath();
    ctx.fill();
    ctx.strokeStyle = "rgba(0, 0, 0, 0.4)"; ctx.lineWidth = 1 / camera.zoom;
    ctx.stroke();
}

function animateAndStrike(hook) {
    const { animation } = hook.cueState;
    const elapsedTime = performance.now() - animation.startTime;
    const progress = Math.min(elapsedTime / animation.duration, 1);
    const easedProgress = 1 - Math.pow(1 - progress, 3);
    const currentPullDistance = animation.initialPullDistance * (1 - easedProgress);
    
    drawCue(hook, currentPullDistance);
    
    if (progress >= 1) {
      hook.pushEvent("apply_force", animation.force);
      hook.cueState.status = 'inactive';
    }
}

function updatePowerBar(hook, pullDistance) {
    const power = Math.min(pullDistance / hook.cueState.MAX_PULL_DISTANCE, 1);
    hook.powerBarElement.style.width = `${power * 100}%`;
}
