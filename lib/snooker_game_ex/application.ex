defmodule SnookerGameEx.Application do
  @moduledoc false
  use Application

  # CORREÇÃO: Aponta para o GameSupervisor no namespace correto.
  alias SnookerGameEx.Engine.GameSupervisor

  @impl true
  def start(_type, _args) do
    children = [
      SnookerGameExWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:snooker_game_ex, :dns_cluster_query) || :ignore},
      {Registry, keys: :unique, name: SnookerGameEx.ParticleRegistry},
      {Registry, keys: :unique, name: SnookerGameEx.GameRegistry},
      {Phoenix.PubSub, name: SnookerGameEx.PubSub},
      {Finch, name: SnookerGameEx.Finch},
      SnookerGameExWeb.Endpoint,
      GameSupervisor
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
