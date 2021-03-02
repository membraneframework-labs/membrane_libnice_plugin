defmodule Membrane.ICE.Bin do
  @moduledoc """
  Bin used for establishing ICE connection, sending and receiving messages.

  ### Architecture and pad semantic
  Both input and output pads are dynamic ones.
  One instance of ICE Bin is responsible for handling only one ICE stream which can have
  multiple components.
  Each pad is responsible for carrying data from/to one component.

  ### Linking using output pad
  To receive messages after establishing ICE connection you have to link ICE Bin to your element
  via `Pad.ref(:output, component_id)`.  `component_id` is an id of component from which your
  element will receive messages. E.g. if you passed as `n_components` 2 it means that there will be
  two components and you can link ICE Bin to your element via `Pad.ref(:output, 1)`
  and `Pad.ref(:output, 2)`.

  **Important**: you can link to ICE Bin using its output pad in any moment you want but if you don't
  want to miss any messages do it before playing your pipeline.

  **Important**: you can't link multiple elements using the same `component_id`. Messages from
  one component can be conveyed only to one element.

  ### Linking using input pad
  To send messages after establishing ICE connection you have to link to ICE Bin via
  `Pad.ref(:input, component_id)`. `component_id` is an id of component which will be used to send
  messages via net. To send data from multiple elements via the same `component_id` you have to
  use [membrane_funnel_plugin](https://github.com/membraneframework/membrane_funnel_plugin).

  ### Messages API
  You can send following messages to ICE Bin:

  - `{:set_remote_credentials, credentials}` - credentials are string in form of "ufrag passwd"

  - `{:set_remote_candidate, candidate, component_id}` - candidate is a string in form of
  SDP attribute i.e. it has prefix "a=" e.g. "a=candidate 1 "

  - `{:parse_remote_sdp, sdp}`

  - `:peer_candidate_gathering_done`

  ### Notifications API
  - `{:new_candidate_full, candidate}`
    Triggered by: starting pipeline i.e. `YourPipeline.play(pid)`

  - `:candidate_gathering_done`
  Triggered by: starting pipeline i.e. `YourPipeline.play(pid)`

  - `{:new_remote_candidate_full, candidate}`
    Triggered by: `{:set_remote_candidate, candidate, component_id}` or `{:parse_remote_sdp, sdp}`

  ### Sending and receiving messages
  To send or receive messages just link to ICE Bin using relevant pads.
  As soon as connection is established your element will receive demands from ICE Sink or
  messages from ICE Source.
  """
  use Membrane.Bin

  alias Membrane.ICE.Connector

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
              turn_servers: [
                default: [],
                description: "List of turn servers"
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
                description:
                  "Options for handshake module. They will be passed to init function of
                handshake_module"
              ]

  def_input_pad :input,
    availability: :on_request,
    caps: :any,
    mode: :pull,
    demand_unit: :buffers

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
      turn_servers: turn_servers,
      controlling_mode: controlling_mode,
      port_range: port_range,
      handshake_module: handshake_module,
      handshake_opts: handshake_opts
    } = options

    {:ok, connector} =
      Connector.start_link(
        parent: self(),
        n_components: n_components,
        stream_name: stream_name,
        stun_servers: stun_servers,
        turn_servers: turn_servers,
        controlling_mode: controlling_mode,
        port_range: port_range,
        handshake_module: handshake_module,
        handshake_opts: handshake_opts
      )

    {:ok, ice} = Connector.get_ice_pid(connector)

    children = [
      ice_source: Membrane.ICE.Source,
      ice_sink: %Membrane.ICE.Sink{ice: ice}
    ]

    spec = %ParentSpec{
      children: children
    }

    {{:ok, spec: spec}, %{:connector => connector}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, _component_id) = pad, _ctx, state) do
    links = [link(:ice_source) |> via_out(pad) |> to_bin_output(pad)]
    {{:ok, spec: %ParentSpec{links: links}}, state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, _component_id) = pad, _ctx, state) do
    links = [link_bin_input(pad) |> via_in(pad) |> to(:ice_sink)]
    {{:ok, spec: %ParentSpec{links: links}}, state}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, %{connector: connector} = state) do
    {:ok, handshake_init_data, credentials} = Connector.run(connector)

    actions =
      handshake_init_data
      |> Enum.map(fn {component_id, init_data} ->
        {:notify, {:handshake_init_data, component_id, init_data}}
      end)

    actions = actions ++ [{:notify, {:local_credentials, credentials}}]
    {{:ok, actions}, state}
  end

  @impl true
  def handle_prepared_to_stopped(_ctx, %{connector: connector} = state) do
    Connector.stop(connector)
    {:ok, state}
  end

  @impl true
  def handle_other(
        {:set_remote_credentials, credentials},
        _ctx,
        %{connector: connector} = state
      ) do
    Connector.set_remote_credentials(connector, credentials)
    {:ok, state}
  end

  @impl true
  def handle_other({:parse_remote_sdp, sdp}, _ctx, %{connector: connector} = state) do
    Connector.parse_remote_sdp(connector, sdp)
    {:ok, state}
  end

  @impl true
  def handle_other(
        {:set_remote_candidate, cand, component_id},
        _ctx,
        %{connector: connector} = state
      ) do
    Connector.set_remote_candidate(connector, cand, component_id)
    {:ok, state}
  end

  @impl true
  def handle_other(:restart_stream, _ctx, %{connector: connector} = state) do
    {:ok, credentials} = Connector.restart_stream(connector)
    {{:ok, notify: {:local_credentials, credentials}}, state}
  end

  @impl true
  def handle_other(:peer_candidate_gathering_done, _ctx, %{connector: connector} = state) do
    Connector.peer_candidate_gathering_done(connector)
    {:ok, state}
  end

  @impl true
  def handle_other(
        {:component_ready, _stream_id, _component_id, _handshake_data} = msg,
        _ctx,
        state
      ) do
    actions = [forward: {:ice_sink, msg}]
    {{:ok, actions}, state}
  end

  @impl true
  def handle_other({:handshake_data, _component_id, _handshake_data} = msg, _ctx, state) do
    {{:ok, forward: {:ice_source, msg}}, state}
  end

  @impl true
  def handle_other({:ice_payload, component_id, _payload} = msg, ctx, state) do
    if Map.has_key?(ctx.pads, Pad.ref(:output, component_id)) do
      {{:ok, forward: {:ice_source, msg}}, state}
    else
      Membrane.Logger.warn("No links for component: #{component_id}. Ignoring incoming message.")
      {:ok, state}
    end
  end

  @impl true
  def handle_other(msg, _ctx, state) do
    {{:ok, notify: msg}, state}
  end
end
