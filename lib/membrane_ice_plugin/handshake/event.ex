defmodule Membrane.ICE.Handshake.Event do
  @type t :: %__MODULE__{
          handshake_data: any()
        }
  defstruct handshake_data: nil
end

defimpl Membrane.EventProtocol, for: Membrane.ICE.Handshake.Event do
  def async?(_x), do: false
  def sticky?(_x), do: false
end
