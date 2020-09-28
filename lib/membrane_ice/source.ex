defmodule Membrane.ICE.Source do
  @moduledoc """
  Element that receives buffers (over UDP or TCP) and sends them on relevant pads.

  For example if buffer was received by component 1 on stream 1 the buffer will be passed
  on pad {1, 1}. The pipeline or bin has to create link to this element after receiving
  {:component_state_ready, stream_id, component_id} message. Doing it earlier will cause an error
  because given component is not in the READY state yet.

  ## Pad semantics
  Each dynamic pad has to be created with id represented by a tuple `{stream_id, component_id}`.
  Receiving data on component with id `component_id` in stream with id `stream_id` will cause in
  conveying this data on pad with id `{stream_id, component_id}`.
  It is important to link to the Source only after receiving message
  `{:component_state_ready, stream_id, component_id}` which indicates that component with id
  `component_id` in stream with `stream_id` is ready to send and receive data.

  ## Interacting with Source
  Interacting with Source is the same as with Sink. Please refer to `Membrane.ICE.Sink` for
  details.

  ### Messages Source is able to process
  Messages Source is able to process are the same as for Sink. Please refer to `Membrane.ICE.Sink`
  for details.

  ### Messages Source sends
  Source sends all messages that Sink sends (please refer to `Membrane.ICE.Sink`) and additionally
  one more:

  - `{:ice_payload, stream_id, component_id, payload}` - new received payload on component with id
  `component_id` in stream with id `stream_id`.

    Triggered by: this message is not triggered by any other message.

  """

  use Membrane.Source

  require Unifex.CNode
  require Membrane.Logger

  alias Membrane.Buffer
  alias Membrane.ICE.Common

  def_options stun_servers: [
                type: [:string],
                default: [],
                description: "List of stun servers in form of ip:port"
              ],
              controlling_mode: [
                type: :bool,
                default: false,
                description: "Refer to RFC 8445 section 4 - Controlling and Controlled Agent"
              ],
              port_range: [
                type: :range,
                default: 0..0,
                description: "The port range to use"
              ],
              handshake_module: [
                type: :module,
                default: nil,
                description: "Module implementing Handshake behaviour"
              ],
              handshake_opts: [
                type: :list,
                default: [],
                description: "opts for handshake"
              ]

  def_output_pad :output,
    availability: :on_request,
    caps: :any,
    mode: :push

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            ice: pid,
            handshake: pid,
            handshake_module: Handshake.t(),
            handshake_state: :in_progress | :finished | :disabled,
            connections: MapSet.t()
          }
    defstruct ice: nil,
              handshake: nil,
              handshake_module: Handshake.Default,
              handshake_state: :in_progress,
              connections: MapSet.new()
  end

  @impl true
  def handle_init(%__MODULE__{handshake_module: Handshake.Default} = options) do
    handle_init(options, :disabled)
  end

  @impl true
  def handle_init(options) do
    handle_init(options, :in_progress)
  end


  defp handle_init(options, handshake_state) do
    %__MODULE__{
      stun_servers: stun_servers,
      controlling_mode: controlling_mode,
      port_range: port_range,
      handshake_module: handshake_module,
      handshake_opts: handshake_opts
    } = options

    {:ok, ice} =
      ExLibnice.start_link(
        parent: self(),
        stun_servers: stun_servers,
        controlling_mode: controlling_mode,
        port_range: port_range
      )

    {:ok, handshake} = handshake_module.start_link(handshake_opts ++ [parent: self(), ice: ice])

    state = %State{ice: ice, handshake: handshake, handshake_module: handshake_module, handshake_state: handshake_state}

    {:ok, state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, {stream_id, component_id}), _ctx, state) do
    if MapSet.member?(state.connections, {stream_id, component_id}) do
      {:ok, state}
    else
      Membrane.Logger.error("""
      Connection for stream: #{stream_id} and component: #{component_id} not established yet.
      Cannot add pad
      """)

      {{:ok, notify: :connection_not_established_yet}, state}
    end
  end

  @impl true
  def handle_other(
        {:ice_payload, stream_id, component_id, payload},
        %{playback_state: :playing} = ctx,
        %State{handshake_state: handshake_state} = state
      ) when handshake_state == :finished or handshake_state == :disabled do
    Membrane.Logger.debug("Received payload: #{Membrane.Payload.size(payload)} bytes")

    actions =
      case Map.get(ctx.pads, Pad.ref(:output, {stream_id, component_id})) do
        nil ->
          Membrane.Logger.warn("""
          Pad for stream: #{stream_id} and component: #{component_id} not
          added yet. Probably your component is not in READY state yet. Ignoring message
          """)

          []

        pad ->
          [buffer: {pad.ref, %Buffer{payload: payload}}]
      end

    {{:ok, actions}, state}
  end

  @impl true
  def handle_other(
        {:ice_payload, _stream_id, _component_id, payload},
        _ctx,
        %State{handshake_state: :in_progress} = state
      ) do
    %State{handshake: handshake, handshake_module: handshake_module} = state
    handshake_module.recv_from_peer(handshake, payload)
    {:ok, state}
  end

  @impl true
  def handle_other({:handshake_finished, _keying_material} = msg, _ctx, state) do
    new_state = %State{state | handshake_state: :finished}
    {{:ok, notify: msg}, new_state}
  end

  @impl true
  def handle_other(
        {:component_state_ready, stream_id, component_id} = msg,
        _ctx,
        %State{handshake: handshake, handshake_module: handshake_module} = state
      ) do
    Membrane.Logger.debug("Component #{component_id} in stream #{stream_id} READY")

    handshake_module.connection_ready(handshake, stream_id, component_id)

    new_connections = MapSet.put(state.connections, {stream_id, component_id})
    new_state = %State{state | connections: new_connections}
    {{:ok, notify: msg}, new_state}
  end

  @impl true
  def handle_other(msg, ctx, state) do
    Common.handle_ice_message(msg, ctx, state)
  end
end
