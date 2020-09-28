defmodule Handshake do

  @type t :: module

  @callback start_link(opts :: term) :: {:ok, pid}

  @callback connection_ready(pid :: pid(), stream_id :: integer, component_id :: integer) :: :ok

  @callback recv_from_peer(pid :: pid(), data :: binary()) :: :ok
end
