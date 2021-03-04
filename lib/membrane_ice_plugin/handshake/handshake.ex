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

  @typedoc """
  Notification sent to pipeline after executing `init/1` function on handshake module
  """
  @type init_notification ::
          {:handshake_init_data, component_id :: non_neg_integer(), init_data :: any()}

  @doc """
  Called only once at Sink/Source preparation.

  `opts` - options specified in `handshake_opts` option in Sink/Source
  `init_data` - any data that will be fired as a notification to pipeline. Notification
  will be of type `t:init_notification/0`
  `state` - state that will be passed to other functions
  `id` - id assigned by ICE plugin. It corresponds to component_id. Has to be used for
  retransmitting packets

  Returning by a peer `:finished` will mark handshake as finished.
  """
  @callback init(id :: pos_integer(), parent :: pid(), opts :: list()) ::
              {:ok, init_data :: any(), state()}
              | {:finished, init_data :: any()}

  @doc """
  Called only once when component changes state to READY i.e. it is able to receive and send data.

  It is a good place to start your handshake.
  """
  @callback connection_ready(state :: state()) :: :ok | {:ok, packets :: binary()}

  @doc """
  Called each time remote data arrives.

  If there is a need to retransmit some data send message `{:retransmit, id, data}`.
  `id` is id assigned by ICE in `init/3` function.
  """
  @callback process(data :: binary(), state :: state()) ::
              :ok
              | {:ok, packets :: binary()}
              | {:hsk_packets, packets :: binary()}
              | {:hsk_finished, hsk_data :: any()}
              | {:hsk_finished, hsk_data :: any(), packets :: binary()}
              | {:error, value :: integer()}

  @doc """
  Determines if given `data` should be treated as handshake packet and passed to `process/2`.
  """
  @callback is_hsk_packet(data :: binary(), state :: state()) :: boolean()
end
