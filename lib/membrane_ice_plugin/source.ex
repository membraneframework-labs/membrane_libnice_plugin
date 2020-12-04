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
    {:ok, %{}}
  end

  @impl true
  def handle_other({:ice_payload, component_id, payload}, _ctx, state) do
    actions = [buffer: {Pad.ref(:output, component_id), %Membrane.Buffer{payload: payload}}]
    {{:ok, actions}, state}
  end

  @impl true
  def handle_other({:handshake_data, component_id, handshake_data}, _ctx, state) do
    actions = [
      event: {Pad.ref(:output, component_id), %Handshake.Event{handshake_data: handshake_data}}
    ]

    {{:ok, actions}, state}
  end
end
