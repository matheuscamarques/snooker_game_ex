defmodule SnookerGameEx.Test.MockNotifier do
  @moduledoc """
  Um notificador mock para testes.
  Implementa o behaviour `SnookerGameEx.GameNotifier` e envia as notificações
  como mensagens para o processo de teste que o invocou.
  O processo de teste deve se registrar usando `Process.put(:test_process_pid, self())`.
  """
  @behaviour SnookerGameEx.GameNotifier

  defp owner_pid, do: Process.get(:test_process_pid)

  @impl SnookerGameEx.GameNotifier
  def notify_particle_update(_game_id, particle) do
    send(owner_pid(), {:particle_update, particle})
    :ok
  end

  @impl SnookerGameEx.GameNotifier
  def notify_particle_removed(_game_id, particle_id) do
    send(owner_pid(), {:particle_removed, particle_id})
    :ok
  end

  @impl SnookerGameEx.GameNotifier
  def notify_ball_pocketed(_game_id, particle_id, ball_data) do
    send(owner_pid(), {:ball_pocketed, particle_id, ball_data})
    :ok
  end
end
