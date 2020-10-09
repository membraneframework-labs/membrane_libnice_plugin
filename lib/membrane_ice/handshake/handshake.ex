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
  Called only once at Sink/Source initialization. It must return pid of handshake module.

  `opts` - options specified in `handshake_opts` option in Sink/Source. This list will additionally
  include following data:
  * parent :: pid() - pid of element calling this function
  * ice :: pid() - pid of ice process. Can be used for sending packets to a remote host
  * stream_id :: integer() - id of stream for which this function is called
  * component_id :: integer() - id of component for which this module will perform handshake
  """
  @callback start_link(opts :: List.t()) :: {:ok, pid}

  @doc """
  Called only once when component is in the READY state i.e. it is able to receive and send data.

  It is a good place to start your handshake.
  """
  @callback connection_ready(pid :: pid()) :: :ok

  @doc """
  Called each time remote data arrives.
  """
  @callback recv_from_peer(pid :: pid(), data :: binary()) :: :ok
end
