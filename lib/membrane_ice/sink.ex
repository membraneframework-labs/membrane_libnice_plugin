defmodule Membrane.ICE.Sink do
  @moduledoc """
  Element that sends buffers (over UDP or TCP) received on different pads to relevant receivers.

  ## Architecture and pad semantic
  Each sink instance own exactly one stream which can have multiple components. There is no
  possibility to add more streams or remove the existing one. User specify number of components
  at Sink initialization by passing relevant option - see `def_options` macro for more
  information.

  Multiple components are handled with dynamic pads. Each time component with id `component_id`
  changes its state to READY (i.e. pipeline receives message
  `{component_state_ready, component_id, handshake_data}` other elements can be linked to the Sink
  using pad with id `component_id`. After successful linking sending data to the Sink on newly
  added pad will cause conveying this data through the net using component with id `component_id`.

  For example if buffer was received on pad 1 the element will send it through component 1 to the
  receiver which then will convey this data through its pad 1 to some other element.

  The pipeline or bin has to create link to this element after receiving
  {:component_state_ready, component_id, handshake_data} message. Doing it earlier will cause an
  error because given component is not in the READY state yet.

  ## Handshakes
  Membrane ICE Plugin provides mechanism for performing handshakes (e.g. DTLS-SRTP) after
  establishing ICE connection. This is done by passing handshake module as on option at Sink/Source
  initialization. Provided handshake module has to implement `Handshake` behaviour. By default
  none handshake is performed. Please refer to `Handshake` module for more information.

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
    - none

  - `:gather_candidates`

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

  Sending some messages to Sink can cause it will start performing some work. Below there are
  listed messages that Sink can send after completing this work:

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
          |> Enum.reduce(%{}, fn component_id, acc ->
            {:ok, pid} = handshake_module.start_link(handshake_opts)
            Map.put(acc, component_id, {pid, handshake_state, nil})
          end)

        state = %Common.State{
          ice: ice,
          controlling_mode: controlling_mode,
          stream_id: stream_id,
          handshakes: handshakes,
          handshake_module: handshake_module
        }

        {:ok, state}

      {:error, cause} ->
        {{:error, cause}, %Common.State{}}
    end
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, component_id) = pad, _ctx, state) do
    if MapSet.member?(state.connections, component_id) do
      {{:ok, demand: pad}, state}
    else
      Membrane.Logger.error("""
      Connection for component: #{component_id} not established yet. Cannot add pad
      """)

      {{:error, :connection_not_established_yet}, state}
    end
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
  def handle_other(msg, ctx, state) do
    Common.handle_ice_message(msg, ctx, state)
  end
end
