defmodule SnookerGameExWeb.SnookerGameLive do
  use SnookerGameExWeb, :live_view

  alias SnookerGameEx.Engine.GameSupervisor, as: Game
  alias SnookerGameEx.Core.GameRules

  @impl true
  def mount(%{"game_id" => game_id}, _session, socket) do
    Game.start_game(game_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(SnookerGameEx.PubSub, "particle_updates:#{game_id}")
      Phoenix.PubSub.subscribe(SnookerGameEx.PubSub, "game_events:#{game_id}")
    end

    socket = assign(socket, game_id: game_id, game_state: %GameRules{})
    {:ok, socket}
  end

  # --- Handlers de Informação (Eventos do Servidor) ---

  @impl true
  def handle_info({:particle_moved, payload}, socket) do
    {:noreply, push_event(socket, "particle_moved", payload)}
  end

  @impl true
  def handle_info({:particle_removed, payload}, socket) do
    {:noreply, push_event(socket, "particle_removed", payload)}
  end

  @impl true
  def handle_info({:game_state_update, rules_state}, socket) do
    {:noreply, assign(socket, game_state: rules_state)}
  end

  @impl true
  def handle_info(:all_balls_stopped, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:ball_pocketed, _id, _ball_data}, socket), do: {:noreply, socket}

  # --- Handlers de Eventos (Ações do Cliente) ---

  @impl true
  def handle_event("apply_force", %{"x" => x, "y" => y}, socket) do
    if socket.assigns.game_state.can_shoot and not socket.assigns.game_state.ball_in_hand do
      game_id = socket.assigns.game_id
      Game.start_shot(game_id)
      Game.apply_force(game_id, 0, {x * 15, y * 15})
    end
    {:noreply, socket}
  end

  @impl true
  def handle_event("reposition_ball", %{"x" => x, "y" => y}, socket) do
    if socket.assigns.game_state.ball_in_hand do
      Game.reposition_cue_ball(socket.assigns.game_id, {x, y})
    end
    {:noreply, socket}
  end

  @impl true
  def handle_event("reset_game", _, socket) do
    Game.restart_game(socket.assigns.game_id)
    {:noreply, socket}
  end

  # --- Renderização e Componentes de Função ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="game-container">
      <div class="game-header">
        <div class="flex justify-between items-center mb-4">
          <h2 class="text-2xl font-bold text-white">Elixir Pool 3D</h2>

          <div class={"player-info player-#{@game_state.current_turn}"}>
            <span class="player-label"><strong>Jogador Atual:</strong></span>
            <span class="player-indicator">
              <.player_display player={@game_state.current_turn} />
            </span>
          </div>
        </div>

        <div class="flex flex-wrap justify-center gap-3 mb-3">
          <div class="status-message">
            <strong>Estado:</strong> <%= @game_state.status_message %>
          </div>

          <%= if @game_state.winner do %>
            <div class="winner-message text-lg">
              <strong>FIM DE JOGO! Vencedor:</strong>
              Jogador <.player_display player={@game_state.winner} />
            </div>
          <% end %>
        </div>

        <div class="rules-hud">
          <h4 class="rules-hud-title">📊 Estado do Jogo</h4>
          <div class="rules-grid">
            <div>Fase do Jogo:</div>
            <div><%= format_game_phase(@game_state.game_phase) %></div>

            <div>Grupos:</div>
            <div><.format_assignments assignments={@game_state.ball_assignments} /></div>

            <div>Pode Jogar:</div>
            <div><.boolean_icon is_true={@game_state.can_shoot} /></div>

            <div>Bola na Mão:</div>
            <div><.boolean_icon is_true={@game_state.ball_in_hand} /></div>

            <div>Falta Cometida:</div>
            <div><.boolean_icon is_true={@game_state.foul_committed} /></div>
          </div>
        </div>
      </div>

      <div
        id="simulation-wrapper"
        phx-hook="CanvasHook"
        data-ball-in-hand={@game_state.ball_in_hand}
        data-can-shoot={@game_state.can_shoot}
        class="perspective-3d"
      >
        <div id="canvas-wrapper">
          <canvas id="physics-canvas" width="1000" height="500"></canvas>
        </div>
        <div class="camera-controls">
          <button id="rotate-btn" title="Rotacionar Ecrã" class="btn">🔄</button>
          <button id="zoom-in-btn" title="Zoom In" class="btn">+</button>
          <button id="zoom-out-btn" title="Zoom Out" class="btn">-</button>
          <button id="reset-view-btn" title="Repor Visão" class="btn">🗘</button>
        </div>
        <div id="d-pad-controls">
          <button id="d-pad-up" class="btn">▲</button>
          <button id="d-pad-left" class="btn">◀</button>
          <button id="d-pad-right" class="btn">▶</button>
          <button id="d-pad-down" class="btn">▼</button>
        </div>
        <div class="power-indicator">
          <div class="power-level" id="power-level"></div>
        </div>
      </div>
      <div class="game-controls">
        <button phx-click="reset_game" class="btn">Reiniciar Jogo</button>
      </div>
    </div>
    """
  end

  defp format_game_phase(phase) do
    phase
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp player_display(assigns) do
    ~H"""
    <%= case @player do
      :player1 -> "1"
      :player2 -> "2"
      _ -> "-"
    end %>
    """
  end

  defp boolean_icon(assigns) do
    ~H"""
    <%= if @is_true do %>
      <span class="text-green-500 font-bold">✓</span>
    <% else %>
      <span class="text-red-500 font-bold">✗</span>
    <% end %>
    """
  end

  defp format_assignments(assigns) do
    ~H"""
    <%= if map_size(@assignments) == 0 do %>
      Mesa Aberta
    <% else %>
      <%= for {player, suit} <- @assignments, reduce: "" do acc ->
            label = "J#{player_display_raw(player)}: #{suit |> to_string() |> String.capitalize()}s"
            if acc == "", do: label, else: acc <> ", " <> label
          end %>
    <% end %>
    """
  end

  defp player_display_raw(player) do
    case player do
      :player1 -> "1"
      :player2 -> "2"
      _ -> "-"
    end
  end
end
