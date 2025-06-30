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
end
