defmodule SnookerGameExWeb.SnookerGameLive do
  @moduledoc """
  The main LiveView for the Snooker Game interface.

  It handles user interactions, such as applying force to the cue ball,
  subscribes to game state updates from the backend via PubSub, and pushes
  those updates to the client for rendering on the HTML canvas.
  """
  use SnookerGameExWeb, :live_view

  alias SnookerGameEx.{CollisionEngine, ParticleSupervisor}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SnookerGameEx.PubSub, "particle_updates")
      Phoenix.PubSub.subscribe(SnookerGameEx.PubSub, "game_events")
    end

    socket =
      assign(socket,
        score: 0,
        message: "Ready to Play"
      )

    {:ok, socket}
  end

  @impl true
  def handle_info({:particle_moved, payload}, socket) do
    {:noreply, push_event(socket, "particle_moved", payload)}
  end

  @impl true
  def handle_info({:ball_pocketed, id, ball_data}, socket) do
    # The `ball_data` variable is now a map like %{number: 8, type: :solid, ...}
    message =
      case ball_data.type do
        :cue ->
          "FALTA! Bola branca na caçapa!"

        _ ->
          "Bola #{ball_data.number} encaçapada!"
      end

    # Example scoring logic
    score =
      case ball_data.type do
        :cue ->
          # Penalty for sinking the cue ball.
          socket.assigns.score - 2

        _ ->
          socket.assigns.score + 1
      end

    # Tell the frontend to remove the rendered ball.
    socket = push_event(socket, "particle_removed", %{id: id})

    {:noreply, assign(socket, score: score, message: message)}
  end

  @impl true
  def handle_event("apply_force", %{"x" => x, "y" => y}, socket) do
    GenServer.cast(SnookerGameEx.Particle.via_tuple(0), {:apply_force, [x * 15, y * 15]})
    {:noreply, assign(socket, message: "Playing...")}
  end

  @impl true
  def handle_event("reset_game", _, socket) do
    ParticleSupervisor.restart()
    CollisionEngine.restart()

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
