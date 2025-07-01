defmodule SnookerGameEx.Rules do
  @moduledoc "BEHAVIOUR para diferentes conjuntos de regras de jogo."
  alias SnookerGameEx.Core.GameRules

  @callback init() :: GameRules.t()
  @callback handle_ball_pocketed(state :: GameRules.t(), ball_data :: map()) :: GameRules.t()
  @callback handle_turn_end(state :: GameRules.t()) :: GameRules.t()
  @callback get_current_state(state :: GameRules.t()) :: GameRules.t()
end
