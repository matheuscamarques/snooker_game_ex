defmodule SnookerGameExWeb.SnookerGameLive do
  use SnookerGameExWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SnookerGameEx.PubSub, "particle_updates")
      Phoenix.PubSub.subscribe(SnookerGameEx.PubSub, "game_events")
    end

    socket =
      assign(socket,
        score: 0,
        message: "Pronto para jogar"
      )

    {:ok, socket}
  end

  @impl true
  def handle_info({:particle_moved, payload}, socket) do
    {:noreply, push_event(socket, "particle_moved", payload)}
  end

  def handle_info({:ball_pocketed, id, color}, socket) do
    message =
      if color == "white" do
        "FALTA! Bola branca caiu!"
      else
        "Bola #{color} encaçapada!"
      end

    score =
      if color != "white" do
        socket.assigns.score + 1
      else
        socket.assigns.score - 2
      end

    {:noreply, assign(socket, score: score, message: message)}
  end

  @impl true
  def handle_event("apply_force", %{"x" => x, "y" => y}, socket) do
    GenServer.cast(SnookerGameEx.Particle.via_tuple(0), {:apply_force, [x * 21, y * 21]})
    {:noreply, assign(socket, message: "Jogando...")}
  end

  def render(assigns) do
    ~H"""
    <div class="game-container">
      <div class="game-header">
        <h2>Sinuca Profissional</h2>
        <div class="game-info">
          <span>Pontuação: {@score}</span>
          <span>{@message}</span>
        </div>
      </div>

      <div id="simulation-wrapper" phx-hook="CanvasHook">
        <canvas id="physics-canvas" width="1000" height="500" />
      </div>

      <div class="game-controls">
        <button phx-click="reset_game">Reiniciar Jogo</button>
      </div>
    </div>
    """
  end
end
