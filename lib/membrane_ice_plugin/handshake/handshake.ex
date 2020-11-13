defmodule Membrane.ICE.Handshake do
  @moduledoc """
  Behaviour that specifies functions that have to be implemented in order to perform handshake
  after establishing ICE connection.

  One instance of this module is responsible for performing handshake only for one component.
  """

  @type t :: module

  @typedoc """
  It is any type that user want it to be passed to other functions of this behaviour.
  """
  @type state :: term()

  @doc """
  Called only once at Sink/Source preparation.

  `opts` - options specified in `handshake_opts` option in Sink/Source
  `state` - state that will be passed to other functions

  Returning by a peer `:finished` will mark handshake as finished and none of the remaining
  functions will be invoked for this peer.
  """
  @callback init(opts :: list()) :: {:ok, state()} | :finished

  @doc """
  Called only once when component changes state to READY i.e. it is able to receive and send data.

  It is a good place to start your handshake. In case of one host don't need to do anything
  and only waits for initialization from its peer it can return `ok` message.
  Meaning of the rest return values is the same as in `recv_from_peer/2`.
  """
  @callback connection_ready(state :: state()) ::
              :ok
              | {:ok, packets :: binary()}
              | {:finished_with_packets, handshake_data :: term(), packets :: binary()}
              | {:finished, handshake_data :: term()}

  @doc """
  Called each time remote data arrives.

  Message `{:ok, packets}` should be returned when peer processed incoming data and generated
  a new one.

  Message `{:finished_with_packets, handshake_data, packets}` should be return by a peer that ends
  its handshake first but it generates also some final packets so that the second peer can end its
  handshake too.

  Packets returned both in `{:finished_with_packets, handshake_data, packets}` and
  `{:finished, handshake_data term()}` messages will be automatically sent to the peer using ICE
  connection.

  `handshake_data` is any data user want to return after finishing handshake.
  """
  @callback recv_from_peer(state :: state(), data :: binary()) ::
              {:ok, packets :: binary()}
              | {:finished_with_packets, handshake_data :: term(), packets :: binary()}
              | {:finished, handshake_data :: term()}
end
