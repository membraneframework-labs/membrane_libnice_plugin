defmodule Membrane.ICE.Sink do
  @moduledoc """
  Element that sends buffers (over UDP or TCP) received on different pads to relevant receivers.
  """

  use Membrane.Sink

  alias Membrane.ICE.Handshake

  require Membrane.Logger

  def_options ice: [
                type: :pid,
                default: nil,
                description: "Pid of ExLibnice instance. It's needed to send packets out."
              ]

  def_input_pad :input,
    availability: :on_request,
    caps: :any,
    mode: :pull,
    demand_unit: :buffers

  @impl true
  def handle_init(options) do
    %__MODULE__{ice: ice} = options

    {:ok, %{:ice => ice, :ready_components => %{}}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, component_id) = pad, _ctx, state) do
    if Map.has_key?(state.ready_components, component_id) do
      {{:ok, get_initial_actions(pad, state.ready_components[component_id])}, state}
    else
      {:ok, state}
    end
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

  @impl true
  def handle_other({:component_ready, stream_id, component_id, handshake_data}, ctx, state) do
    state = Map.put(state, :stream_id, stream_id)
    state = Bunch.Struct.put_in(state, [:ready_components, component_id], handshake_data)

    pad = Pad.ref(:input, component_id)

    if Map.has_key?(ctx.pads, pad) do
      {{:ok, get_initial_actions(pad, handshake_data)}, state}
    else
      {:ok, state}
    end
  end

  defp get_initial_actions(pad, handshake_data) do
    [demand: pad, event: {pad, %Handshake.Event{handshake_data: handshake_data}}]
  end
end
