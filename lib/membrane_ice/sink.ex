defmodule Membrane.ICE.Sink do
  @moduledoc """
  Element that sends buffers (over UDP or TCP) received on different pads to relevant receivers.

  For example if buffer was received on pad 1 the element will send it through component 1.
  The pipeline or bin has to create link to this element after receiving
  {:component_state_ready, component_id, handshake_data} message. Doing it earlier will cause an error
  because given component is not in the READY state yet.

  ## Pad semantic

  Each dynamic pad has to be created with id which is the `component_id`.
  Conveying data to the Sink using pad with id  `component_id` will cause sending
  this data on `component_id`.
  It is important to link to the Sink only after receiving message
  `{:component_state_ready, component_id, handshake_data}` which indicates that component with id
  `component_id` is ready to send and receive data.

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

  - `:get_local_credentials`

    Result notifications:
    - `{:local_credentials, credentials}`

  - `{:set_remote_credentials, credentials}`

    Result notifications:
    - none in case of success

  - `:gather_candidates`

    Result notifications:
     - none in case of success

  - `:peer_candidate_gathering_done`

    Result notifications:
    - none in case of success

  - `{:set_remote_candidate, candidate, component_id}`

    Result notifications:
    - none in case of success
    - `{:error, :failed_to_parse_sdp_string}`
    - `{:error, :failed_to_set}`

  ### Messages Sink sends

  Sending some messages to Sink can cause it will start performing some work. Below there are
  listed messages that Sink can send:

  - `{:new_candidate_full, candidate}`

    Triggered by: `:gather_candidates`

  - `{:new_remote_candidate_full, candidate}`

    Triggered by: `{:set_remote_candidate, candidate, component_id}`

  - `:candidate_gathering_done`

    Triggered by: `:gather_candidates`

  - `{:new_selected_pair, component_id, lfoundation, rfoundation}`

    Triggered by: `{:set_remote_candidate, candidate, component_id}`

  - `{:component_state_failed, stream_id, component_id}`

    Triggered by: `{:set_remote_candidate, candidate, component_id}`

  - `{:component_state_ready, stream_id, component_id}`

    Triggered by: `{:set_remote_candidate, candidate, component_id}`

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

  def_input_pad :input,
    availability: :on_request,
    caps: :any,
    mode: :pull,
    demand_unit: :buffers

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
  def handle_other(msg, ctx, state) do
    Common.handle_ice_message(msg, ctx, state)
  end

  @impl true
  def handle_pad_added(
        Pad.ref(:input, component_id) = pad,
        _ctx,
        %State{stream_id: stream_id} = state
      ) do
    if MapSet.member?(state.connections, {stream_id, component_id}) do
      {{:ok, demand: pad}, state}
    else
      Membrane.Logger.error("""
      Connection for component: #{component_id} not established yet. Cannot add pad
      """)

      {{:error, :connection_not_established_yet}, state}
    end
  end

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
end
