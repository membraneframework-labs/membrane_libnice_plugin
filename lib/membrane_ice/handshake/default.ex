defmodule Membrane.ICE.Handshake.Default do
  @moduledoc """
  Module by default used in Sink/Source for performing handshake. It does nothing so no handshake
  is in fact performed.
  """

  @behaviour Membrane.ICE.Handshake

  @impl true
  def init(_opts) do
    :finished
  end

  @impl true
  def connection_ready(_ctx) do
    {:finished, nil}
  end

  @impl true
  def recv_from_peer(_ctx, _data) do
    {:finished, nil}
  end
end
