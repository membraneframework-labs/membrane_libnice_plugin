defmodule Membrane.ICE.Sink do
  @moduledoc """
  Element that sends buffers (over UDP or TCP) received on different pads to relevant receivers.
  """

  use Membrane.Sink

  alias Membrane.ICE.Handshake
  alias Membrane.Funnel

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

    {:ok,
     %{
       ice: ice,
       ready_components: MapSet.new(),
       finished_hsk: %{},
       component_id_to_turn_port: %{}
     }}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, component_id), ctx, state),
    do: maybe_send_demands(component_id, ctx, state)

  @impl true
  def handle_event(Pad.ref(:input, component_id) = pad, %Funnel.NewInputEvent{}, _ctx, state) do
    if Map.has_key?(state.finished_hsk, component_id) do
      hsk_data = state.finished_hsk[component_id]
      event = {pad, %Handshake.Event{handshake_data: hsk_data}}
      {{:ok, event: event}, state}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_event(_pad, _event, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_write(
        Pad.ref(:input, component_id) = pad,
        %Membrane.Buffer{payload: payload},
        %{playback_state: :playing},
        %{ice: ice, stream_id: stream_id} = state
      ) do
    with %{used_turn_pid: turn_pid} when is_pid(turn_pid) <- state,
         <<first_byte, _tail::binary>> when first_byte in [144, 128] <- payload do
      send(
        turn_pid,
        {:ice_payload, payload, state.component_id_to_turn_port[component_id]}
      )

      {{:ok, demand: pad}, state}
    else
      _ ->
        case ExLibnice.send_payload(ice, stream_id, component_id, payload) do
          :ok ->
            {{:ok, demand: pad}, state}

          {:error, cause} ->
            {{:ok, notify: {:could_not_send_payload, cause}}, state}
        end
    end
  end

  @impl true
  def handle_write(_pad, _buffer, %{playback_state: playback_state}, state) do
    Membrane.Logger.debug("Can't send message in playback state: #{playback_state}. Ignoring.")
    {:ok, state}
  end

  @impl true
  def handle_other({:component_state_ready, stream_id, component_id, port}, ctx, state) do
    state =
      Map.merge(state, %{
        stream_id: stream_id,
        ready_components: MapSet.put(state.ready_components, component_id),
        component_id_to_turn_port: Map.put(state.component_id_to_turn_port, component_id, port)
      })
    maybe_send_demands(component_id, ctx, state)
  end

  @impl true
  def handle_other({:hsk_finished, component_id, hsk_data}, ctx, state) do
    state = put_in(state.finished_hsk[component_id], hsk_data)
    maybe_send_demands(component_id, ctx, state)
  end

  def handle_other({:turn_server_started, turn_pid}, _ctx, state) do
    # TODO: terminate unused TURNs after every ICE restart

    state =
      Map.update(
        state,
        :turn_pids,
        [turn_pid],
        &[turn_pid | &1]
      )

    {:ok, state}
  end

  def handle_other({:used_turn_pid, used_turn_pid}, _ctx, state) do
    {:ok, Map.put(state, :used_turn_pid, used_turn_pid)}
  end

  defp maybe_send_demands(component_id, ctx, state) do
    pad = Pad.ref(:input, component_id)
    # if something is linked, component is ready and handshake is done then send demands
    if Map.has_key?(ctx.pads, pad) and MapSet.member?(state.ready_components, component_id) and
         Map.has_key?(state.finished_hsk, component_id) do
      hsk_data = Map.get(state.finished_hsk, component_id)

      actions = [
        demand: pad,
        event: {pad, %Handshake.Event{handshake_data: hsk_data}}
      ]

      {{:ok, actions}, state}
    else
      {:ok, state}
    end
  end
end
