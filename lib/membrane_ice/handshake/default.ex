defmodule Handshake.Default do
  @behaviour Handshake

  @impl true
  def start_link(_opts) do
    {:ok, nil}
  end

  @impl true
  def connection_ready(_pid, _stream_id, _component_id) do
    :ok
  end

  @impl true
  def recv_from_peer(_pid, _data) do
    :ok
  end
end
