defmodule Membrane.ICE.Bin do
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
      source: %Membrane.ICE.Source{
        n_components: n_components
      },
      sink: %Membrane.ICE.Sink{
        ice: ice,
        n_components: n_components
      }
    ]

    spec = %ParentSpec{
      children: children
    }

    {{:ok, spec: spec}, %{connector => connector}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, _) = pad, _ctx, state) do
    links = [link_bin_input(pad) |> to(:source)]
    {{:ok, spec: %ParentSpec{links: links}}, state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, _) = pad, _ctx, state) do
    links = [link_bin_input(pad) |> to(:sink)]
    {{:ok, spec: %ParentSpec{links: links}}, state}
  end

  @impl true
  def handle_prepared_to_playing(ctx, %{connector: connector} = state) do
    check_pads(:input)
    check_pads(:output)

    {:local_credentials, credentials} = Connector.run(connector)
    {{:ok, notify: {:local_credentials, credentials}}, state}
  end

  defp check_pads(pads_type) do
    unlinked_components =
      Enum.reject(1..state.n_components, &Map.has_key?(ctx.pads, Pad.ref(pads_type, &1)))

    if Enum.empty?(unlinked_components) do
      {:ok, state}
    else
      raise "Pads #{pads_type} for components no. #{Enum.join(unlinked_components, ", ")} haven't been linked"
    end
  end

  @impl true
  def handle_other({:component_ready, stream_id, component_id, handshake_data} = msg, ctx, state) do
    {{:ok, forward: {:sink, msg}}, state}
  end

  @impl true
  def handle_other({:ice_payload, _component_id, _payload} = msg, ctx, state) do
    {{:ok, forward: {:source, msg}}, state}
  end

  @impl true
  def handle_other(msg, ctx, state) do
    {{:ok, notify: msg}, state}
  end
end
