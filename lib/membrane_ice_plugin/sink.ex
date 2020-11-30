defmodule Membrane.ICE.Sink do
  @moduledoc """
  Element that sends buffers (over UDP or TCP) received on different pads to relevant receivers.

  Multiple components are handled with dynamic pads. Other elements can be linked to the Sink
  using pad with id `component_id`. After successful linking sending data to the Sink on newly
  added pad will cause conveying this data through the net using component with id `component_id`.

  For example if buffer was received on pad 1 the element will send it through component 1 to the
  receiver which then will convey this data through its pad 1 to some other element.

  Other elements can be linked to the Sink in any moment but before playing pipeline. Playing your
  pipeline is possible only after linking all pads. E.g. if your stream has 2 components you have to
  link to the Sink using two dynamic pads with ids 1 and 2 and after this you can play your pipeline.


  ### Sending messages

  Sending messages (over the net) was described in `Architecture and pad semantic` section.
  Here we only want to notice that Sink can fail to send message. In this case notification
  `{:error, :failed_to_send}` is fired to pipeline/bin.
  """

  use Membrane.Sink

  alias Membrane.ICE.Common

  require Membrane.Logger

  def_options ice: [
                type: :pid,
                default: nil,
                description: "Pid of ExLibnice instance"
              ]

  def_input_pad :input,
    availability: :on_request,
    caps: :any,
    mode: :pull,
    demand_unit: :buffers

  @impl true
  def handle_init(options) do
    %__MODULE__{ice: ice} = options

    {:ok, %{:ice => ice}}
  end

  @impl true
  def handle_write(
        Pad.ref(:input, component_id) = pad,
        %Buffer{payload: payload},
        _ctx,
        %{stream_id: stream_id} = state
      ) do
    case ExLibnice.send_payload(ice, stream_id, component_id, payload) do
      :ok ->
        Membrane.Logger.debug("Sent payload: #{payload_size} bytes")
        {{:ok, demand: pad}, state}

      {:error, cause} ->
        {{:ok, notify: {:could_not_send_payload, cause}}, state}
    end
  end

  def handle_notification({:component_ready, stream_id, component_id}, from, ctx, state) do
    Membrane.Logger.debug("Got component_id #{component_id}. Sending demands...")
    actions = [demand: Pad.ref(:input, component_id)]
    # FIXME handle stream_id in a better way
    {{:ok, actions}, Map.put(state, :stream_id, stream_id)}
  end
end
