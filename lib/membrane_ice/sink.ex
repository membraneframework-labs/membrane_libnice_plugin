defmodule Membrane.Element.ICE.Sink do
  use Membrane.Sink
  use Membrane.Element.ICE.Common

  alias Membrane.Buffer

  def_input_pad :input,
    availability: :always,
    caps: :any,
    mode: :pull,
    demand_unit: :buffers

  @impl true
  def handle_other(
        {:new_selected_pair, _stream_id, _component_id, _lfoundation, _rfoundation},
        _context,
        state
      ) do
    {{:ok, demand: :input}, state}
  end

  def handle_write(
        :input,
        %Buffer{payload: payload, metadata: metadata},
        _context,
        %{cnode: cnode} = state
      ) do
    stream_id = Map.get(metadata, :stream_id, nil)
    component_id = Map.get(metadata, :component_id, nil)

    if !stream_id || !component_id do
      {{:error, :no_stream_or_component_id}, state}
    else
      case Unifex.CNode.call(cnode, :send_payload, [stream_id, component_id, payload]) do
        :ok -> {{:ok, demand: :input}, state}
        {:error, cause} -> {{:error, cause}, state}
      end
    end
  end
end
