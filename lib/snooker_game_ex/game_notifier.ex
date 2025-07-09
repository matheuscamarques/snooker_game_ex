defmodule SnookerGameEx.GameNotifier do
  @moduledoc """
  O Port de SAÍDA (Driven Port) que define como o jogo notifica
  o mundo exterior sobre eventos.
  """

  alias SnookerGameEx.Core.GameState

  @doc "Notifica que uma partícula se moveu ou mudou de estado."
  @callback notify_particle_update(game_id :: String.t(), particle :: GameState.t()) :: :ok

  @doc "Notifica que uma partícula foi removida (ex: encaçapada)."
  @callback notify_particle_removed(game_id :: String.t(), particle_id :: any()) :: :ok

  @doc "Notifica que uma bola foi encaçapada."
  @callback notify_ball_pocketed(
              game_id :: String.t(),
              particle_id :: any(),
              ball_data :: map()
            ) :: :ok

  @doc "Notifica que o estado das regras do jogo foi atualizado."
  @callback notify_game_state_update(game_id :: String.t(), rules_state :: any()) :: :ok

  @doc "Notifica que todas as bolas pararam de se mover."
  @callback notify_all_balls_stopped(game_id :: String.t()) :: :ok
end
