defmodule SnookerGameExWeb.SnookerGameLive do
  @moduledoc """
  The main LiveView for the Snooker Game interface.

  It handles user interactions, such as applying force to the cue ball,
  subscribes to game state updates from the backend via PubSub, and pushes
  those updates to the client for rendering on the HTML canvas.
  """
  alias SnookerGameEx.GameSupervisor
  use SnookerGameExWeb, :live_view

  @impl true
  def mount(%{"game_id" => game_id}, _session, socket) do
    # Inicia o jogo para este ID se ainda não estiver rodando
    GameSupervisor.start_game(game_id)

    if connected?(socket) do
      # Inscreve-se nos tópicos específicos do jogo
      Phoenix.PubSub.subscribe(SnookerGameEx.PubSub, "particle_updates:#{game_id}")
      Phoenix.PubSub.subscribe(SnookerGameEx.PubSub, "game_events:#{game_id}")
    end

    socket =
      assign(socket,
        score: 0,
        message: "Bem-vindo à sala #{game_id}!",
        # Armazena o ID do jogo no socket
        game_id: game_id
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
  def handle_event("hold_ball", id, socket) do
    # Passa o game_id ao interagir com a partícula
    GenServer.cast(SnookerGameEx.Particle.via_tuple(socket.assigns.game_id, id), :hold)
    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_force", %{"x" => x, "y" => y}, socket) do
    # A bola branca (ID 0) também precisa do game_id
    GenServer.cast(
      SnookerGameEx.Particle.via_tuple(socket.assigns.game_id, 0),
      {:apply_force, [x * 15, y * 15]}
    )

    {:noreply, assign(socket, message: "Jogando...")}
  end

  @impl true
  def handle_event("reset_game", _, socket) do
    # Reinicia o jogo específico
    SnookerGameEx.GameInstanceSupervisor.restart(socket.assigns.game_id)
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
