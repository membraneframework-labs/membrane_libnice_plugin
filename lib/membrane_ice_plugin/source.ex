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
    {:ok, %{handshake_data: nil}}
  end

  @impl true
  def handle_pad_added(_pad, _ctx, %{handshake_data: nil} = state) do
    {:ok, state}
  end

  @impl true
  def handle_pad_added(
        Pad.ref(:output, _component_id) = pad,
        _ctx,
        %{handshake_data: handshake_data} = state
      ) do
    {{:ok, event: {pad, %Handshake.Event{handshake_data: handshake_data}}}, state}
  end

  @impl true
  def handle_other({:ice_payload, component_id, payload}, _ctx, state) do
    actions = [buffer: {Pad.ref(:output, component_id), %Membrane.Buffer{payload: payload}}]
    {{:ok, actions}, state}
  end

  @impl true
  def handle_other({:handshake_data, component_id, handshake_data}, ctx, state) do
    pad = Pad.ref(:output, component_id)

    actions =
      if Map.has_key?(ctx.pads, pad) do
        [event: {pad, %Handshake.Event{handshake_data: handshake_data}}]
      else
        []
      end

    {{:ok, actions}, Map.put(state, :handshake_data, handshake_data)}
  end
end
