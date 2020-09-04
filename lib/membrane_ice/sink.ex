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
  Below there are described messages that can be send to Sink and by Sink.

  ### Messages Sink is able to process

  Each result that Sink produces is conveyed to the pipeline/bin as notification. Below there are
  described messages Sink is able process:

  - `{:add_stream, n_components}` - add streams with `n_components`.

    Result notifications:
    - `{:stream_id, stream_id}` - `stream_id` indicates new stream id.
    - `{:error, :failed_to_add_stream}`
    - `{:error, :failed_to_attach_recv}`

  - `{:add_stream, n_components, name}` - same as above but additionally sets name for the new stream.

    Result notifications:
    - `{:stream_id, stream_id}` - `stream_id` indicates new stream id.
    - `{:error, :failed_to_add_stream}`
    - `{:error, :invalid_stream_or_duplicate_name}` - in case of named stream. In fact this error
    always should be related with duplicated stream name.
    - `{:error, :failed_to_attach_recv}`

  - `{:remove_stream, stream_id}` - removes stream with `stream_id` if exists.

    Result notifications: none.

  - `:generate_local_sdp` - generates a SDP string containing the local candidates and credentials
  for all streams and components.

    Result notifications:
    - `{:local_sdp, sdp}` - it is important that returned SDP will not contain
    any codec lines and the 'm' line will not list any payload types. If the stream was created
    without the name the `m` line will contain `-` mark instead. There will not also be `o` field.
    Please refer to `libnice` documentation for `nice_agent_generate_local_sdp` function.

  - `{:parse_remote_sdp, remote_sdp}` - parses a remote SDP string setting credentials and
  remote candidates for proper streams and components. It is important that `m` line does not
  contain `-` mark but name of the stream.

    Result notifications:
    - `{:parse_remote_sdp_ok, added_cand_num}`

  - `{:get_local_credentials, stream_id}` - returns local credentials for stream with id `stream_id`.

    Result notifications:
    - `{:local_credentials, credentials}` - credentials are in form of `'ufrag pwd'`

  - `{:set_remote_credentials, credentials, stream_id}` - sets remote credentials for stream with
  `stream_id`. Credentials has to be passed in form of `'ufrag pwd'`.

    Result notifications:
    - none in case of success

  - `{:gather_candidates, stream_id}` - starts gathering candidates process for stream with id
  `stream_id`.

    Result notifications:
     - none in case of success

  - `{:peer_candidate_gathering_done, stream_id}` - indicates that all remotes candidates for stream
  with id `stream_id` have been passed. This allows for components in given stream to change
  their state to `COMPONENT_STATE_FAILED` (in fact there is a bug please refer to
  [#120](https://gitlab.freedesktop.org/libnice/libnice/-/issues/120))

    Result notifications:
    - none in case of success
    - `{:error, :stream_not_found}`

  - `{:set_remote_candidate, candidate, stream_id, component_id}` - sets remote candidate for
  component with id `component_id` in stream with id `stream_id`. Candidate has to be passed as
  SDP string.

    Result notifications:
    - none in case of success
    - `{:error, :failed_to_parse_sdp_string}`
    - `{:error, :failed_to_set}` - memory allocation error or invalid component

  ### Messages Sink sends

  Sending some messages to Sink can cause it will start performing some work. Below there are
  described messages that Sink can send:

  - `{:new_candidate_full, candidate}` - new local candidate.

    Triggered by: `{:gather_candidates, stream_id}`

  - `{:new_remote_candidate_full, candidate}` - new remote (prflx) candidate.

    Triggered by: `{:set_remote_candidate, candidate, stream_id, component_id}`

  - `{:candidate_gathering_done, stream_id}` - gathering candidates for stream with `stream_id`
  has been done

    Triggered by: `{:gather_candidates, stream_id}`

  - `{:new_selected_pair, stream_id, component_id, lfoundation, rfoundation}` - new selected pair.

    Triggered by: `{:set_remote_candidate, candidate, stream_id, component_id}`

  - `{:component_state_failed, stream_id, component_id}` - component with id `component_id` in stream
  with id `stream_id` has changed state to FAILED.

    Triggered by: `{:set_remote_candidate, candidate, stream_id, component_id}`

  - `{:component_state_ready, stream_id, component_id}` - component with id `component_id` in stream
  with id `stream_id` has changed state to READY i.e. it is ready to receive and send data.

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
              turn_servers: [
                type: [:string],
                default: [],
                description: "List of turn servers in form of ip:port:proto:username:passwd"
              ],
              controlling_mode: [
                type: :bool,
                default: false,
                description: "Refer to RFC 8445 section 4 - Controlling and Controlled Agent"
              ],
              min_port: [
                type: :unsigned,
                default: 0,
                description: "The minimum port to use"
              ],
              max_port: [
                type: :unsigned,
                default: 0,
                description: "The maximum port to use"
              ]

  def_input_pad :input,
    availability: :on_request,
    caps: :any,
    mode: :pull,
    demand_unit: :buffers

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            cnode: Unifex.CNode.t(),
            connections: MapSet.t()
          }
    defstruct cnode: nil,
              connections: MapSet.new()
  end

  @impl true
  def handle_init(%__MODULE__{} = options) do
    %__MODULE__{
      stun_servers: stun_servers,
      turn_servers: turn_servers,
      controlling_mode: controlling_mode,
      min_port: min_port,
      max_port: max_port
    } = options

    {:ok, cnode} = Unifex.CNode.start_link(:native)

    :ok =
      Unifex.CNode.call(cnode, :init, [
        stun_servers,
        turn_servers,
        controlling_mode,
        min_port,
        max_port
      ])

    state = %State{
      cnode: cnode
    }

    {:ok, state}
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

  @impl true
  def handle_other({:component_state_ready, stream_id, component_id} = msg, _ctx, state) do
    Membrane.Logger.debug("Component #{component_id} in stream #{stream_id} READY")

    new_connections = MapSet.put(state.connections, {stream_id, component_id})
    new_state = %State{state | connections: new_connections}
    {{:ok, notify: msg}, new_state}
  end

  @impl true
  def handle_other(msg, ctx, state) do
    Common.handle_ice_message(msg, ctx, state)
  end

  def handle_write(
        Pad.ref(:input, {stream_id, component_id}) = pad,
        %Buffer{payload: payload},
        _context,
        %{cnode: cnode} = state
      ) do
    payload_size = Membrane.Payload.size(payload)

    case Unifex.CNode.call(cnode, :send_payload, [stream_id, component_id, payload]) do
      :ok ->
        Membrane.Logger.debug("Sent payload: #{payload_size} bytes")

        {{:ok, demand: pad}, state}

      {:error, cause} ->
        Membrane.Logger.warn("Couldn't send payload: #{inspect(cause)}")

        {{:ok, notify: {:could_not_send_payload, payload_size}}, state}
    end
  end
end
