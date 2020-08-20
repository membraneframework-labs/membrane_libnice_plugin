defmodule Example.AddressProvider do
  use Membrane.Filter

  alias Membrane.Buffer

  def_input_pad :input,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers,
    caps: :any

  def_output_pad :output,
    availability: :always,
    mode: :pull,
    caps: :any

  @impl true
  def handle_demand(:output, size, :buffers, _context, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(
        :input,
        %Buffer{metadata: metadata} = buffer,
        _context,
        state
      ) do
    metadata = metadata |> Map.put(:stream_id, 1) |> Map.put(:component_id, 1)
    buffer = Map.put(buffer, :metadata, metadata)
    {{:ok, buffer: {:output, buffer}}, state}
  end
end
