defmodule SnookerGameExWeb.GameChannel do
  use SnookerGameExWeb, :channel

  # CORREÇÃO: Aponta para a implementação do Port, não para o behaviour.
  alias SnookerGameEx.Engine.GameSupervisor, as: Game

  # CORREÇÃO: Adicionada a função join/3 obrigatória.
  @impl true
  def join("game:" <> game_id, _payload, socket) do
    # Inicia o jogo se necessário
    Game.start_game(game_id)

    # Inscreve-se nos tópicos para este jogo específico
    Phoenix.PubSub.subscribe(SnookerGameEx.PubSub, "particle_updates:#{game_id}")
    Phoenix.PubSub.subscribe(SnookerGameEx.PubSub, "game_events:#{game_id}")

    {:ok, %{message: "Joined game #{game_id}"}, assign(socket, :game_id, game_id)}
  end

  @impl true
  def handle_in("player_hit", %{"force" => [fx, fy]}, socket) do
    game_id = socket.assigns.game_id
    # Bola branca
    ball_id = 0

    # Comunicação via Port (agora funciona)
    Game.apply_force(game_id, ball_id, {fx, fy})

    {:noreply, socket}
  end

  # Encaminha os eventos do PubSub para o cliente do canal
  @impl true
  def handle_info({:particle_moved, payload}, socket) do
    push(socket, "particle_moved", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:particle_removed, payload}, socket) do
    push(socket, "particle_removed", payload)
    {:noreply, socket}
  end
end
