defmodule Membrane.ICE.Source do
  @moduledoc """
  Element that receives buffers (over UDP or TCP) and sends them on relevant pads.

  For example if buffer was received by component 1 the buffer will be passed
  on pad 1. The pipeline or bin has to create link to this element after receiving
  {:component_state_ready, component_id, handshake_data} message. Doing it earlier will cause an error
  because given component is not in the READY state yet.

  ## Pad semantics
  Each dynamic pad has to be created with id which is the `component_id`.
  Receiving data on component with id `component_id`  will cause in
  conveying this data on pad with id `component_id`.
  It is important to link to the Source only after receiving message
  `{:component_state_ready, component_id, handshake_data}` which indicates that component with id
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

  - `{:ice_payload, component_id, payload}` - new received payload on component with id
  `component_id`.

    Triggered by: this message is not triggered by any other message.

  """

  use Membrane.Source

  require Unifex.CNode
  require Membrane.Logger

  alias Membrane.Buffer
  alias Membrane.ICE.Common

  def_options n_components: [
                type: :integer,
                default: 1,
                description: "Number of components that will be created in the stream"
              ],
              stream_name: [
                type: :string,
                default: "",
                description: "Name of the stream"
              ],
              stun_servers: [
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

    @type handshake_state :: :in_progress | :finished | :disabled
    @type handshake_data :: term
    @type stream_id :: integer()
    @type component_id :: integer()

    @type t :: %__MODULE__{
            ice: pid,
            stream_id: stream_id,
            handshakes: %{{stream_id(), component_id()} => {pid, handshake_state, handshake_data}},
            handshake_module: Handshake.t(),
            connections: MapSet.t()
          }
    defstruct ice: nil,
              stream_id: nil,
              handshakes: %{},
              handshake_module: Handshake.Default,
              connections: MapSet.new()
  end

  @impl true
  def handle_init(%__MODULE__{handshake_module: Handshake.Default} = options) do
    handle_init(options, :finished)
  end

  @impl true
  def handle_init(options) do
    handle_init(options, :in_progress)
  end

  defp handle_init(options, handshake_state) do
    %__MODULE__{
      n_components: n_components,
      stream_name: stream_name,
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

    case ExLibnice.add_stream(ice, n_components, stream_name) do
      {:ok, stream_id} ->
        handshakes =
          1..n_components
          |> Enum.reduce(%{}, fn x, acc ->
            {:ok, pid} =
              handshake_module.start_link(
                handshake_opts ++
                  [parent: self(), ice: ice, component_id: x]
              )

            Map.put(acc, {stream_id, x}, {pid, handshake_state, nil})
          end)

        state = %State{
          ice: ice,
          stream_id: stream_id,
          handshakes: handshakes,
          handshake_module: handshake_module
        }

        {:ok, state}

      {:error, cause} ->
        {{:error, cause}, %State{}}
    end
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, component_id), _ctx, %State{stream_id: stream_id} = state) do
    if MapSet.member?(state.connections, {stream_id, component_id}) do
      {:ok, state}
    else
      Membrane.Logger.error("""
      Connection for component: #{component_id} not established yet. Cannot add pad
      """)

      {{:ok, notify: :connection_not_established_yet}, state}
    end
  end

  @impl true
  def handle_other(
        {:ice_payload, _stream_id, component_id, payload},
        %{playback_state: :playing} = ctx,
        state
      ) do
    Membrane.Logger.debug("Received payload: #{Membrane.Payload.size(payload)} bytes")

    actions =
      case Map.get(ctx.pads, Pad.ref(:output, component_id)) do
        nil ->
          Membrane.Logger.warn("""
          Pad for component: #{component_id} not added yet. Probably your component is not in READY
          state yet. Ignoring message
          """)

          []

        pad ->
          [buffer: {pad.ref, %Buffer{payload: payload}}]
      end

    {{:ok, actions}, state}
  end

  @impl true
  def handle_other({:ice_payload, stream_id, component_id, payload}, _ctx, state) do
    key = {stream_id, component_id}

    %State{
      handshakes: %{^key => {pid, :in_progress, _handshake_data}},
      handshake_module: handshake_module
    } = state

    handshake_module.recv_from_peer(pid, payload)
    {:ok, state}
  end

  @impl true
  def handle_other(
        {:handshake_finished, component_id, keying_material},
        _ctx,
        %State{stream_id: stream_id} = state
      ) do
    key = {stream_id, component_id}

    %State{handshakes: %{^key => {dtls_pid, _handshake_state, _handshake_data}} = handshakes} =
      state

    handshakes =
      Map.put(handshakes, {stream_id, component_id}, {dtls_pid, :finished, keying_material})

    new_state = %State{state | handshakes: handshakes}

    if MapSet.member?(state.connections, {stream_id, component_id}) do
      {{:ok, notify: {:component_state_ready, component_id, keying_material}}, new_state}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_other({:component_state_ready, stream_id, component_id}, _ctx, state) do
    Membrane.Logger.debug("Component #{component_id} READY")

    key = {stream_id, component_id}

    %State{
      handshakes: handshakes,
      handshake_module: handshake_module
    } = state

    {pid, handshake_state, handshake_data} = Map.get(handshakes, key)

    new_connections = MapSet.put(state.connections, {stream_id, component_id})
    new_state = %State{state | connections: new_connections}

    if handshake_state == :finished do
      {{:ok, notify: {:component_state_ready, component_id, handshake_data}}, new_state}
    else
      handshake_module.connection_ready(pid, stream_id, component_id)
      {:ok, new_state}
    end
  end

  @impl true
  def handle_other(msg, ctx, state) do
    Common.handle_ice_message(msg, ctx, state)
  end
end
