defmodule Membrane.ICE.Bin do
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
    {:local_credentials, credentials} = Connector.run(connector)
    {{:ok, notify: {:local_credentials, credentials}}, state}
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
  def handle_other(
        {:set_remote_candidate, cand, component_id},
        _ctx,
        %{connector: connector} = state
      ) do
    Connector.set_remote_candidate(connector, cand, component_id)
    {:ok, state}
  end

  @impl true
  def handle_other(
        {:component_ready, _stream_id, component_id, handshake_data} = msg,
        ctx,
        state
      ) do
    actions = [forward: {:ice_sink, msg}, notify: {:component_ready, component_id, handshake_data}]
    {{:ok, actions}, state}
  end

  @impl true
  def handle_other({:ice_payload, component_id, _payload} = msg, ctx, state) do
    if Map.has_key?(ctx.pads, Pad.ref(:output, component_id)) do
      {{:ok, forward: {:ice_source, msg}}, state}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_other(msg, _ctx, state) do
    {{:ok, notify: msg}, state}
  end
end
