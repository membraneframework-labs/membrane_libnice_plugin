defmodule Membrane.ICE.Handshake.Default do
  @moduledoc """
  Module by default used in Sink/Source for performing handshake. It does nothing so no handshake
  is in fact performed.
  """

  @behaviour Membrane.ICE.Handshake

  @impl true
  def start_link(_opts) do
    {:ok, nil}
  end

  @impl true
  def connection_ready(_pid) do
    :ok
  end

  @impl true
  def recv_from_peer(_pid, _data) do
    :ok
  end
end
