defmodule Membrane.ICE.Source do
  @moduledoc """
  Element that receives buffers (over UDP or TCP) and sends them on relevant pads.

  As Source works analogously to the Sink here we only describe features that are specific
  for Source.

  ## Architecture and pad semantics
  Multiple components are handled with dynamic pads. Receiving data on component with id
  `component_id` will cause in conveying this data on pad with id `component_id`. Other elements
  can be linked to the Source in any moment but before playing pipeline.

  ## Interacting with Source
  Interacting with Source is the same as with Sink. Please refer to `Membrane.ICE.Sink` for
  details.

  ### Messages Source is able to process
  Messages Source is able to process are the same as for Sink. Please refer to `Membrane.ICE.Sink`
  for details.

  ### Messages Source sends
  Source sends all messages that Sink sends. Please refer to `Membrane.ICE.Sink` for details.
  """

  use Membrane.Source

  alias Membrane.Buffer
  alias Membrane.ICE.Common
  alias Membrane.ICE.Common.State
  alias Membrane.ICE.Handshake

  require Unifex.CNode
  require Membrane.Logger

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
                default: Handshake.Default,
                description: "Module implementing Handshake behaviour"
              ],
              handshake_opts: [
                type: :list,
                default: [],
                description: "Options for handshake module. They will be passed to start_link
                function of handshake_module"
              ]

  def_output_pad :output,
    availability: :on_request,
    caps: :any,
    mode: :push

  @impl true
  def handle_init(options) do
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

    state = %State{
      ice: ice,
      controlling_mode: controlling_mode,
      n_components: n_components,
      stream_name: stream_name,
      handshake_module: handshake_module,
      handshake_opts: handshake_opts
    }

    {:ok, state}
  end

  @impl true
  def handle_stopped_to_prepared(ctx, state) do
    Common.handle_stopped_to_prepared(ctx, state)
  end

  @impl true
  def handle_prepared_to_playing(ctx, state) do
    pad_states = 1..state.n_components |> Enum.map(&Map.has_key?(ctx.pads, Pad.ref(:output, &1)))

    if false in pad_states do
      {{:error, "There are components without corresponding linked pads"}, state}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_other(
        {:ice_payload, _stream_id, component_id, payload} = msg,
        %{playback_state: :playing} = ctx,
        %State{handshakes: handshakes} = state
      ) do
    Membrane.Logger.debug("Received payload: #{Membrane.Payload.size(payload)} bytes")

    {_handshake_ctx, handshake_state, _handshake_data} = Map.get(handshakes, component_id)

    if handshake_state != :finished do
      Common.handle_ice_message(msg, ctx, state)
    else
      actions = [buffer: {Pad.ref(:output, component_id), %Buffer{payload: payload}}]
      {{:ok, actions}, state}
    end
  end

  @impl true
  def handle_other({:ice_payload, stream_id, component_id, payload}, _ctx, state) do
    %State{
      ice: ice,
      handshakes: handshakes,
      handshake_module: handshake_module
    } = state

    {handshake_state, handshake_status, _handshake_data} = Map.get(handshakes, component_id)

    if handshake_status != :finished do
      res = handshake_module.recv_from_peer(handshake_state, payload)

      {{finished?, handshake_data}, new_state} =
        Common.parse_result(res, ice, stream_id, component_id, handshakes, handshake_state, state)

      if finished? and MapSet.member?(state.connections, component_id) do
        {{:ok, notify: {:component_state_ready, component_id, handshake_data}}, new_state}
      else
        {:ok, new_state}
      end
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_other({:component_state_ready, stream_id, component_id}, _ctx, state) do
    Membrane.Logger.debug("Component #{component_id} READY")

    %State{
      ice: ice,
      handshakes: handshakes,
      handshake_module: handshake_module
    } = state

    {handshake_state, handshake_status, handshake_data} = Map.get(handshakes, component_id)

    new_connections = MapSet.put(state.connections, component_id)
    new_state = %State{state | connections: new_connections}

    if handshake_status != :finished do
      res = handshake_module.connection_ready(handshake_state)

      {{finished?, handshake_data}, new_state} =
        Common.parse_result(
          res,
          ice,
          stream_id,
          component_id,
          handshakes,
          handshake_state,
          new_state
        )

      if finished? do
        {{:ok, notify: {:component_state_ready, component_id, handshake_data}}, new_state}
      else
        {:ok, new_state}
      end
    else
      {{:ok, notify: {:component_state_ready, component_id, handshake_data}}, new_state}
    end
  end

  @impl true
  def handle_other(msg, ctx, state) do
    Common.handle_ice_message(msg, ctx, state)
  end
end
