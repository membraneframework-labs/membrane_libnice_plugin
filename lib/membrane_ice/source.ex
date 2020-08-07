defmodule Membrane.Element.ICE.Source do
  use Membrane.Source
  use Membrane.Element.ICE.Common

  alias Membrane.Buffer

  def_output_pad :output,
    availability: :always,
    caps: :any,
    mode: :push

  @impl true
  def handle_other(
        {:new_selected_pair, _stream_id, _component_id, _lfoundation, _rfoundation} = msg,
        _context,
        state
      ) do
    {{:ok, notify: msg}, state}
  end

  @impl true
  def handle_other(
        {:ice_payload, stream_id, component_id, payload},
        %{playback_state: :playing},
        state
      ) do
    metadata = %{:stream_id => stream_id, :component_id => component_id}
    actions = [buffer: {:output, %Buffer{payload: payload, metadata: metadata}}]
    {{:ok, actions}, state}
  end
end
