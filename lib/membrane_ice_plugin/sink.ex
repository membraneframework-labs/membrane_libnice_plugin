defmodule Membrane.ICE.Sink do
  @moduledoc """
  Element that sends buffers (over UDP or TCP) received on different pads to relevant receivers.
  """

  use Membrane.Sink

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
        %Membrane.Buffer{payload: payload},
        _ctx,
        %{ice: ice, stream_id: stream_id} = state
      ) do
    case ExLibnice.send_payload(ice, stream_id, component_id, payload) do
      :ok ->
        {{:ok, demand: pad}, state}

      {:error, cause} ->
        {{:ok, notify: {:could_not_send_payload, cause}}, state}
    end
  end

  def handle_other({:component_ready, stream_id, component_id, _handshake_data}, _ctx, state) do
    Membrane.Logger.debug("Got component_id #{component_id}. Sending demands...")
    actions = [demand: Pad.ref(:input, component_id)]
    # FIXME handle stream_id in a better way
    {{:ok, actions}, Map.put(state, :stream_id, stream_id)}
  end
end
