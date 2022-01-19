defmodule Membrane.Libnice.Handshake.Default do
  @moduledoc """
  Module by default used after establishing Libnice connection. It does nothing so no handshake
  is in fact performed.
  """

  @behaviour Membrane.Libnice.Handshake

  @impl true
  def init(_id, _parent, _opts), do: {:finished, nil}

  @impl true
  def connection_ready(_state), do: :ok

  @impl true
  def process(_data, _state), do: :ok

  @impl true
  def is_hsk_packet(_data, _state), do: false

  @impl true
  def stop(_state), do: :ok
end
