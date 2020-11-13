defmodule Membrane.ICE.Sink do
  @moduledoc """
  Element that sends buffers (over UDP or TCP) received on different pads to relevant receivers.

  ## Architecture and pad semantic
  Each sink instance owns exactly one stream which can have multiple components. There is no
  possibility to add more streams or remove the existing one. User specify number of components
  at Sink initialization by passing relevant option - see `def_options` macro for more
  information.

  Multiple components are handled with dynamic pads. Other elements can be linked to the Sink
  using pad with id `component_id`. After successful linking sending data to the Sink on newly
  added pad will cause conveying this data through the net using component with id `component_id`.

  For example if buffer was received on pad 1 the element will send it through component 1 to the
  receiver which then will convey this data through its pad 1 to some other element.

  Other elements can be linked to the Sink in any moment but before playing pipeline. Playing your
  pipeline is possible only after linking all pads. E.g. if your stream has 2 components you have to
  link to the Sink using two dynamic pads with ids 1 and 2 and after this you can play your pipeline.

  ## Handshakes
  Membrane ICE Plugin provides mechanism for performing handshakes (e.g. DTLS-SRTP) after
  establishing ICE connection. This is done by passing handshake module as on option at Sink/Source
  initialization. Provided handshake module has to implement `Membrane.ICE.Handshake` behaviour.
  By default none handshake is performed. Please refer to `Membrane.ICE.Handshake` module for more
  information.

  ## Interacting with Sink

  Interacting with Sink is held by sending it proper messages. Some of them are synchronous i.e.
  the result is returned immediately while other are asynchronous i.e. Sink will notify us about
  result after completing some work.
  Below there are listed messages that can be send to Sink and by Sink. As these messages are
  analogous to those sent by `ExLibnice` library please refer to its documentation for
  more details.

  ### Messages Sink is able to process

  Each result that Sink produces is conveyed to the pipeline/bin as notification. Below there are
  listed messages Sink is able process:

  - `:generate_local_sdp`

    Result notifications:
    - `{:local_sdp, sdp}`

  - `{:parse_remote_sdp, remote_sdp}`

    Result notifications:
    - `{:parse_remote_sdp_ok, added_cand_num}`

  - `{:set_remote_credentials, credentials}`

    Result notifications:
    - none

  - `:peer_candidate_gathering_done`

    Result notifications:
    - none

  - `{:set_remote_candidate, candidate, component_id}`

    Result notifications:
    - none in case of success
    - `{:error, :failed_to_parse_sdp_string}`
    - `{:error, :failed_to_set}`

  ### Messages Sink sends

  Sending some messages to Sink can cause it will start performing some work. Below there are listed
  notifications that the sink sends after handling incoming messages:

  - `{:new_candidate_full, candidate}`

    Triggered by: starting pipeline i.e. `YourPipeline.play(pid)`

  - `{:new_remote_candidate_full, candidate}`

    Triggered by: `{:set_remote_candidate, candidate, component_id}`

  - `:candidate_gathering_done`

    Triggered by: starting pipeline i.e. `YourPipeline.play(pid)`

  - `{:new_selected_pair, component_id, lfoundation, rfoundation}`

    Triggered by: `{:set_remote_candidate, candidate, component_id}`

  - `{:component_state_failed, stream_id, component_id}`

    Triggered by: `{:set_remote_candidate, candidate, component_id}`

  - `{:component_state_ready, component_id, handshake_data}`

    Triggered by: `{:set_remote_candidate, candidate, component_id}`

  ### Sending messages

  Sending messages (over the net) was described in `Architecture and pad semantic` section.
  Here we only want to notice that Sink can fail to send message. In this case notification
  `{:error, :failed_to_send}` is fired to pipeline/bin.
  """

  use Membrane.Sink

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
  def handle_prepared_to_playing(ctx, state) do
    Common.handle_prepared_to_playing(ctx, state, :input)
  end

  @impl true
  def handle_write(
        Pad.ref(:input, component_id) = pad,
        %Buffer{payload: payload},
        _context,
        %{ice: ice, stream_id: stream_id} = state
      ) do
    payload_size = Membrane.Payload.size(payload)

    case ExLibnice.send_payload(ice, stream_id, component_id, payload) do
      :ok ->
        Membrane.Logger.debug("Sent payload: #{payload_size} bytes")
        {{:ok, demand: pad}, state}

      {:error, cause} ->
        {{:ok, notify: {:could_not_send_payload, cause}}, state}
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
        actions = prepare_actions(component_id, handshake_data)
        {{:ok, actions}, new_state}
      else
        {:ok, new_state}
      end
    else
      actions = prepare_actions(component_id, handshake_data)
      {{:ok, actions}, new_state}
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
        actions = prepare_actions(component_id, handshake_data)
        {{:ok, actions}, new_state}
      else
        {:ok, new_state}
      end
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_other(msg, ctx, state) do
    Common.handle_ice_message(msg, ctx, state)
  end

  defp prepare_actions(component_id, handshake_data) do
    [
      notify: {:component_state_ready, component_id, handshake_data},
      demand: Pad.ref(:input, component_id)
    ]
  end
end
