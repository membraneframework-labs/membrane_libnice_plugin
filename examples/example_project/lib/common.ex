defmodule Example.Common do
  require Membrane.Logger

  def handle_notification({:local_credentials, _credentials} = msg, _from, _ctx, state) do
    Membrane.Logger.info("#{inspect(msg)}")
    {:ok, state}
  end

  def handle_notification({:new_candidate_full, _candidate} = msg, _from, _ctx, state) do
    Membrane.Logger.info("#{inspect(msg)}")
    {:ok, state}
  end

  def handle_notification(
        {:new_selected_pair, _component_id, _lfoundation, _rfoundation} = msg,
        _from,
        _ctx,
        state
      ) do
    Membrane.Logger.info("#{inspect(msg)}")
    {:ok, state}
  end

  def handle_notification(
        {:component_state_ready, component_id, _handshake_data} = msg,
        _from,
        _ctx,
        _state
      ) do
    Membrane.Logger.info("#{inspect(msg)}")
    new_state = %{:ready_component => component_id}
    {:ok, new_state}
  end

  def handle_notification(notification, from, _ctx, state) do
    Membrane.Logger.warn("other notification: #{inspect(notification)}} from: #{inspect(from)}")
    {:ok, state}
  end
end
