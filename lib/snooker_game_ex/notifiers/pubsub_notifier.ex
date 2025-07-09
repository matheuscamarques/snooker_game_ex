defmodule SnookerGameEx.Notifiers.PubSubNotifier do
  @moduledoc """
  ADAPTER: Implementação do port `GameNotifier` usando Phoenix.PubSub.
  """
  @behaviour SnookerGameEx.GameNotifier

  alias SnookerGameEx.Core.GameState
  alias SnookerGameEx.Core.GameRules

  @impl SnookerGameEx.GameNotifier
  def notify_particle_update(game_id, %GameState{} = particle) do
    payload = %{
      id: particle.id,
      pos: particle.pos,
      vel: particle.vel,
      radius: particle.radius,
      color: particle.color,
      spin_angle: particle.spin_angle,
      roll_distance: particle.roll_distance
    }

    Phoenix.PubSub.broadcast(
      SnookerGameEx.PubSub,
      "particle_updates:#{game_id}",
      {:particle_moved, payload}
    )
  end

  @impl SnookerGameEx.GameNotifier
  def notify_particle_removed(game_id, particle_id) do
    Phoenix.PubSub.broadcast(
      SnookerGameEx.PubSub,
      "particle_updates:#{game_id}",
      {:particle_removed, %{id: particle_id}}
    )
  end

  @impl SnookerGameEx.GameNotifier
  def notify_ball_pocketed(game_id, particle_id, ball_data) do
    Phoenix.PubSub.broadcast(
      SnookerGameEx.PubSub,
      "game_events:#{game_id}",
      {:ball_pocketed, particle_id, ball_data}
    )
  end

  @impl SnookerGameEx.GameNotifier
  def notify_game_state_update(game_id, %GameRules{} = rules_state) do
    Phoenix.PubSub.broadcast(
      SnookerGameEx.PubSub,
      "game_events:#{game_id}",
      {:game_state_update, rules_state}
    )
  end

  @impl SnookerGameEx.GameNotifier
  def notify_all_balls_stopped(game_id) do
    Phoenix.PubSub.broadcast(
      SnookerGameEx.PubSub,
      "game_events:#{game_id}",
      :all_balls_stopped
    )
  end
end
