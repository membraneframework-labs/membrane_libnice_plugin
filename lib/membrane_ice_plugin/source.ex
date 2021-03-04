defmodule Membrane.ICE.Source do
  @moduledoc """
  Element that convey buffers received over net (TCP or UDP) to relevant pads.
  """

  use Membrane.Source

  alias Membrane.ICE.Handshake

  require Membrane.Logger

  def_output_pad :output,
    availability: :on_request,
    caps: :any,
    mode: :push

  @impl true
  def handle_init(_opts) do
    {:ok, %{components_hsk_data: %{}}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, component_id) = pad, _ctx, state) do
    if Map.has_key?(state.components_hsk_data, component_id) do
      event = %Handshake.Event{hsk_data: state.components_hsk_data[component_id]}
      {{:ok, event: {pad, event}}, state}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_other(
        {:ice_payload, component_id, payload},
        %{playback_state: :playing} = ctx,
        state
      ) do
    pad = Pad.ref(:output, component_id)

    if Map.has_key?(ctx.pads, pad) do
      {{:ok, [buffer: {pad, %Membrane.Buffer{payload: payload}}]}, state}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_other(
        {:ice_payload, _component_id, _payload},
        %{playback_state: playback_state},
        state
      ) do
    Membrane.Logger.debug("Received message in playback state: #{playback_state}. Ignoring.")
    {:ok, state}
  end

  @impl true
  def handle_other({:hsk_finished, component_id, hsk_data}, ctx, state) do
    pad = Pad.ref(:output, component_id)
    state = put_in(state, [:components_hsk_data, component_id], hsk_data)

    if Map.has_key?(ctx.pads, pad) do
      {{:ok, [event: {pad, %Handshake.Event{hsk_data: hsk_data}}]}, state}
    else
      {:ok, state}
    end
  end
end
