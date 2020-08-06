defmodule Membrane.Element.ICE.Sink do
  use Membrane.Sink
  use Membrane.Element.ICE.Common

  def_input_pad :input,
    availability: :on_request,
    caps: :any,
    mode: :pull,
    demand_unit: :buffers


end
