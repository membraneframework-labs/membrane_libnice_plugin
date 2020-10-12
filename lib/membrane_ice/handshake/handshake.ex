defmodule Membrane.ICE.Handshake do
  @moduledoc """
  Behaviour that specifies functions that have to be implemented in order to perform handshake
  after establishing ICE connection.

  Module implementing this behaviour must work as separate process and will be spawned
  for each component in Sink/Source stream. Therefore one instance of such module is responsible
  for performing handshake only for one component.
  """

  @type t :: module

  @doc """
  Called only once at Sink/Source initialization. It must return pid of a handshake module.

  `opts` - options specified in `handshake_opts` option in Sink/Source
  """
  @callback start_link(opts :: list()) :: {:ok, pid}

  @doc """
  Called only once and only for element working in the controlling mode when its component is in
  the READY state i.e. it is able to receive and send data.

  This function has to return initial handshake packets so it is a good place to start your
  handshake.
  """
  @callback connection_ready(pid :: pid()) :: {:ok, packets :: binary()}

  @doc """
  Called each time remote data arrives.

  Message `{:finished_with_packets, handshake_data, packets}` should be return by a peer that ends
  its handshake first but it generates also some final packets so that the second peer can end its
  handshake too.

  Packets returned both in `{:finished_with_packets, handshake_data, packets}` and
  `{:finished, handshake_data term()}` messages will be automatically sent to the peer using ICE
  connection.
  """
  @callback recv_from_peer(pid :: pid(), data :: binary()) ::
              {:ok, packets :: binary()}
              | {:finished_with_packets, handshake_data :: term(), packets :: binary()}
              | {:finished, handshake_data :: binary()}
end
