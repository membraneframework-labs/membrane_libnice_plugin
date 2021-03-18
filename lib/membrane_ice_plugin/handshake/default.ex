defmodule Membrane.ICE.Handshake.Default do
  @moduledoc """
  Module by default used after establishing ICE connection. It does nothing so no handshake
  is in fact performed.
  """

  @behaviour Membrane.ICE.Handshake

  @impl true
  def init(_id, _parent, _opts), do: {:finished, nil}

  @impl true
  def connection_ready(_state), do: :ok

  @impl true
  def process(_data, _state), do: :ok

  @impl true
  def is_hsk_packet(_data, _state), do: false
end
