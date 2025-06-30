defmodule SnookerGameExWeb.SnookerGameLive do
  use SnookerGameExWeb, :live_view

  alias SnookerGameEx.Engine.GameSupervisor, as: Game

  @impl true
  def mount(%{"game_id" => game_id}, _session, socket) do
    Game.start_game(game_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(SnookerGameEx.PubSub, "particle_updates:#{game_id}")
      Phoenix.PubSub.subscribe(SnookerGameEx.PubSub, "game_events:#{game_id}")
    end

    socket =
      assign(socket,
        score: 0,
        message: "Bem-vindo à sala #{game_id}!",
        game_id: game_id
      )

    {:ok, socket}
  end

  @impl true
  def handle_info({:particle_moved, payload}, socket) do
    {:noreply, push_event(socket, "particle_moved", payload)}
  end

  @impl true
  def handle_info({:particle_removed, payload}, socket) do
    {:noreply, push_event(socket, "particle_removed", payload)}
  end

  @impl true
  def handle_info({:ball_pocketed, _id, ball_data}, socket) do
    message =
      case ball_data.type do
        :cue -> "FALTA! Bola branca na caçapa!"
        _ -> "Bola #{ball_data.number} encaçapada!"
      end

    score =
      case ball_data.type do
        :cue -> socket.assigns.score - 2
        _ -> socket.assigns.score + 1
      end

    {:noreply, assign(socket, score: score, message: message)}
  end

  # CORREÇÃO: A cláusula agora aceita o `id` diretamente, sem o mapa.
  @impl true
  def handle_event("hold_ball", id, socket) do
    Game.hold_ball(socket.assigns.game_id, id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_force", %{"x" => x, "y" => y}, socket) do
    Game.apply_force(socket.assigns.game_id, 0, {x * 15, y * 15})
    {:noreply, assign(socket, message: "Jogando...")}
  end

  @impl true
  def handle_event("reset_game", _, socket) do
    Game.restart_game(socket.assigns.game_id)
    {:noreply, assign(socket, score: 0, message: "Jogo Reiniciado!")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="game-container">
      <div class="game-header">
        <h2>Elixir Pool</h2>
        <div class="game-info">
          <span>Score: {@score}</span>
          <span>{@message}</span>
        </div>
      </div>
      <div id="simulation-wrapper" phx-hook="CanvasHook">
        <div id="canvas-wrapper">
          <canvas id="physics-canvas" width="1000" height="500" />
        </div>
        <div class="camera-controls">
          <button id="rotate-btn" title="Rotacionar Tela">🔄</button>
          <button id="zoom-in-btn" title="Zoom In">+</button>
          <button id="zoom-out-btn" title="Zoom Out">-</button>
          <button id="reset-view-btn" title="Resetar Visão">🗘</button>
        </div>
        <div id="d-pad-controls">
          <button id="d-pad-up">▲</button>
          <button id="d-pad-left">◀</button>
          <button id="d-pad-right">▶</button>
          <button id="d-pad-down">▼</button>
        </div>
      </div>
      <div class="game-controls">
        <button phx-click="reset_game">Reset Game</button>
      </div>
    </div>
    """
  end
end
