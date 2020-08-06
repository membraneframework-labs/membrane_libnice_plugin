defmodule Membrane.Element.ICE.Source do
  use Membrane.Source
  use Membrane.Element.ICE.Common

  def_output_pad :output,
    availability: :on_request,
    caps: :any,
    mode: :push
end
