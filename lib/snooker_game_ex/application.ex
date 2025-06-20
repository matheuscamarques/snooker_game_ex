defmodule SnookerGameEx.Application do
  @moduledoc """
  The main application module for the Snooker Game.

  It starts and supervises all the necessary processes for the game to run,
  including the web endpoint, PubSub, and the core game simulation engine.
  """

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SnookerGameExWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:snooker_game_ex, :dns_cluster_query) || :ignore},
      # Registry para partículas (pode ser usado globalmente com chaves de jogo)
      {Registry, keys: :unique, name: SnookerGameEx.ParticleRegistry},
      # Novo Registry para instâncias de jogos
      {Registry, keys: :unique, name: SnookerGameEx.GameRegistry},
      {Phoenix.PubSub, name: SnookerGameEx.PubSub},
      {Finch, name: SnookerGameEx.Finch},
      SnookerGameExWeb.Endpoint,
      # Inicia o supervisor principal dos jogos
      SnookerGameEx.GameSupervisor
    ]

    opts = [strategy: :one_for_one, name: SnookerGameEx.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SnookerGameExWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
