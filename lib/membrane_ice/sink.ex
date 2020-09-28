defmodule Membrane.ICE.Sink do
  @moduledoc """
  Element that sends buffers (over UDP or TCP) received on different pads to relevant receivers.

  For example if buffer was received on pad {1, 1} the element will send it through component 1
  on stream 1. The pipeline or bin has to create link to this element after receiving
  {:component_state_ready, stream_id, component_id} message. Doing it earlier will cause an error
  because given component is not in the READY state yet.

  ## Pad semantic

  Each dynamic pad has to be created with id represented by a tuple `{stream_id, component_id}`.
  Conveying data to the Sink using pad with id `{stream_id, component_id}` will cause sending
  this data on `component_id` in `stream_id`.
  It is important to link to the Sink only after receiving message
  `{:component_state_ready, stream_id, component_id}` which indicates that component with id
  `component_id` in stream with `stream_id` is ready to send and receive data.

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

  - `{:add_stream, n_components}`

    Result notifications:
    - `{:stream_id, stream_id}`
    - `{:error, :failed_to_add_stream}`
    - `{:error, :failed_to_attach_recv}`

  - `{:add_stream, n_components, name}`

    Result notifications:
    - `{:stream_id, stream_id}`
    - `{:error, :failed_to_add_stream}`
    - `{:error, :invalid_stream_or_duplicate_name}`
    - `{:error, :failed_to_attach_recv}`

  - `{:remove_stream, stream_id}`

    Result notifications: none.

  - `:generate_local_sdp`

    Result notifications:
    - `{:local_sdp, sdp}`

  - `{:parse_remote_sdp, remote_sdp}`

    Result notifications:
    - `{:parse_remote_sdp_ok, added_cand_num}`

  - `{:get_local_credentials, stream_id}`

    Result notifications:
    - `{:local_credentials, credentials}`

  - `{:set_remote_credentials, credentials, stream_id}`

    Result notifications:
    - none in case of success

  - `{:gather_candidates, stream_id}`

    Result notifications:
     - none in case of success

  - `{:peer_candidate_gathering_done, stream_id}`

    Result notifications:
    - none in case of success
    - `{:error, :stream_not_found}`

  - `{:set_remote_candidate, candidate, stream_id, component_id}`

    Result notifications:
    - none in case of success
    - `{:error, :failed_to_parse_sdp_string}`
    - `{:error, :failed_to_set}`

  ### Messages Sink sends

  Sending some messages to Sink can cause it will start performing some work. Below there are
  listed messages that Sink can send:

  - `{:new_candidate_full, candidate}`

    Triggered by: `{:gather_candidates, stream_id}`

  - `{:new_remote_candidate_full, candidate}`

    Triggered by: `{:set_remote_candidate, candidate, stream_id, component_id}`

  - `{:candidate_gathering_done, stream_id}`

    Triggered by: `{:gather_candidates, stream_id}`

  - `{:new_selected_pair, stream_id, component_id, lfoundation, rfoundation}`

    Triggered by: `{:set_remote_candidate, candidate, stream_id, component_id}`

  - `{:component_state_failed, stream_id, component_id}`

    Triggered by: `{:set_remote_candidate, candidate, stream_id, component_id}`

  - `{:component_state_ready, stream_id, component_id}`

    Triggered by: `{:set_remote_candidate, candidate, stream_id, component_id}`

  ### Sending messages

  Sending messages (over the Internet) was described in `Pad semantic` section. Here we only want
  to notice that Sink can fail to send message. In this case notification
  `{:error, :failed_to_send}` is fired to pipeline/bin.
  """

  use Membrane.Sink

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

  def_input_pad :input,
    availability: :on_request,
    caps: :any,
    mode: :pull,
    demand_unit: :buffers

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
              handshake_state: :started,
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
  def handle_other({:ice_payload, _stream_id, _component_id, payload}, _ctx, %State{handshake_state: :in_progress} = state) do
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
  def handle_other(msg, ctx, state) do
    Common.handle_ice_message(msg, ctx, state)
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, {stream_id, component_id}) = pad, _ctx, state) do
    if MapSet.member?(state.connections, {stream_id, component_id}) do
      {{:ok, demand: pad}, state}
    else
      Membrane.Logger.error("""
      Connection for stream: #{stream_id} and component: #{component_id} not established yet.
      Cannot add pad
      """)

      {{:error, :connection_not_established_yet}, state}
    end
  end

  def handle_write(
        Pad.ref(:input, {stream_id, component_id}) = pad,
        %Buffer{payload: payload},
        _context,
        %{ice: ice} = state
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
end
