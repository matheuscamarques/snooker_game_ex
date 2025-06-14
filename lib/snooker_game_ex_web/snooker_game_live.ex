defmodule SnookerGameExWeb.SnookerGameLive do
  @moduledoc """
  The main LiveView for the Snooker Game interface.

  It handles user interactions, such as applying force to the cue ball,
  subscribes to game state updates from the backend via PubSub, and pushes
  those updates to the client for rendering on the HTML canvas.
  """
  use SnookerGameExWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # If the client is connected, subscribe to updates.
    if connected?(socket) do
      # For rendering ball movements.
      Phoenix.PubSub.subscribe(SnookerGameEx.PubSub, "particle_updates")
      # For game logic events like scoring.
      Phoenix.PubSub.subscribe(SnookerGameEx.PubSub, "game_events")
    end

    # Initialize the assigns for the view.
    socket =
      assign(socket,
        score: 0,
        message: "Ready to Play"
      )

    {:ok, socket}
  end

  @impl true
  def handle_info({:particle_moved, payload}, socket) do
    # Quando uma partícula se move, envia o evento diretamente para o CanvasHook.
    {:noreply, push_event(socket, "particle_moved", payload)}
  end

  @impl true
  def handle_info({:ball_pocketed, id, color}, socket) do
    # Lida com a lógica do jogo quando uma bola é encaçapada.
    message =
      if color == "white" do
        "FALTA! Bola branca na caçapa!"
      else
        "Bola #{color} encaçapada!"
      end

    # Exemplo simples de pontuação
    score =
      if color != "white" do
        socket.assigns.score + 1
      else
        # Penalidade por encaçapar a bola branca.
        socket.assigns.score - 2
      end

    # --- AÇÃO IMPORTANTE ---
    # Envia um evento para o frontend para remover a bola da renderização.
    socket = push_event(socket, "particle_removed", %{id: id})

    {:noreply, assign(socket, score: score, message: message)}
  end

  @impl true
  def handle_event("apply_force", %{"x" => x, "y" => y}, socket) do
    # This event is triggered from the `CanvasHook` when the user strikes the cue ball.
    # We cast a message to the white ball (ID 0) to apply the force.
    # The multiplication factor is a "magic number" to tune the shot strength.
    GenServer.cast(SnookerGameEx.Particle.via_tuple(0), {:apply_force, [x * 21, y * 21]})
    {:noreply, assign(socket, message: "Playing...")}
  end

  def render(assigns) do
    ~H"""
    <div class="game-container">
      <div class="game-header">
        <h2>Professional Snooker</h2>
        <div class="game-info">
          <span>Score: {@score}</span>
          <span>{@message}</span>
        </div>
      </div>

      <div id="simulation-wrapper" phx-hook="CanvasHook">
        <canvas id="physics-canvas" width="1000" height="500" />
      </div>

      <div class="game-controls">
        <button phx-click="reset_game">Reset Game</button>
      </div>
    </div>
    """
  end
end
