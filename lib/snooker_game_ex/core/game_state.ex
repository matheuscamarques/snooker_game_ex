defmodule SnookerGameEx.Core.GameState do
  @moduledoc """
  Define as structs de dados puras que representam o estado do jogo.
  Estes são os "substantivos" do nosso domínio.
  """

  @enforce_keys [:id, :pos, :vel, :radius, :mass, :color]
  defstruct [
    :id,
    :pos,
    :vel,
    :radius,
    :mass,
    :color,
    spin_angle: 0.0,
    roll_distance: 0.0
  ]

  @typedoc "Representa uma única partícula (bola) no jogo."
  @type t :: %__MODULE__{
          id: any,
          pos: list(float),
          vel: list(float),
          radius: float,
          mass: float,
          color: map,
          spin_angle: float,
          roll_distance: float
        }
end
