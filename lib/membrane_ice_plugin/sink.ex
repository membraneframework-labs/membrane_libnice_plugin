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
    demand_unit: :buffers,
    options: [
      component_id: [
        spec: non_neg_integer(),
        default: 1,
        description: """
        Component id to send messages out.
        """
      ]
    ]

  @impl true
  def handle_init(options) do
    %__MODULE__{ice: ice} = options

    {:ok, %{:ice => ice, :ready_components => %{}}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, _ref) = pad, ctx, state) do
    %{component_id: component_id} = ctx.pads[pad].options

    if component_id in Map.keys(state.ready_components) do
      {{:ok, get_actions([pad], state.ready_components[component_id])}, state}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_write(
        Pad.ref(:input, _ref) = pad,
        %Membrane.Buffer{payload: payload},
        ctx,
        %{ice: ice, stream_id: stream_id} = state
      ) do
    %{component_id: component_id} = ctx.pads[pad].options

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
    ready_components = Map.put(state.ready_components, component_id, handshake_data)
    state = Map.put(state, :ready_components, ready_components)

    pads =
      ctx.pads
      |> Enum.filter(fn {_k, v} ->
        v[:options][:component_id] == component_id
      end)
      |> Enum.map(fn {k, _v} -> k end)

    if Enum.empty?(pads) do
      {:ok, state}
    else
      {{:ok, get_actions(pads, handshake_data)}, state}
    end
  end

  defp get_actions(pads, handshake_data) do
    pads
    |> Enum.flat_map(fn pad ->
      [demand: pad, event: {pad, %Handshake.Event{handshake_data: handshake_data}}]
    end)
  end
end
