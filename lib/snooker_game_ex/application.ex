defmodule SnookerGameEx.Application do
  @moduledoc """
  The main application module for the Snooker Game.

  It starts and supervises all the necessary processes for the game to run,
  including the web endpoint, PubSub, and the core game simulation engine.
  """
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SnookerGameExWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:snooker_game_ex, :dns_cluster_query) || :ignore},
      {Registry, keys: :unique, name: SnookerGameEx.ParticleRegistry},
      {Phoenix.PubSub, name: SnookerGameEx.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: SnookerGameEx.Finch},
      # Start a worker by calling: SnookerGameEx.Worker.start_link(arg)
      # {SnookerGameEx.Worker, arg},
      # Start to serve requests, typically the last entry
      SnookerGameExWeb.Endpoint,
      # Corrected Order: Start the Engine before the ParticleSupervisor
      # to ensure the ETS table exists when particles are initialized.
      SnookerGameEx.CollisionEngine,
      SnookerGameEx.ParticleSupervisor
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SnookerGameEx.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SnookerGameExWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
