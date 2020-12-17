defmodule Membrane.ICE.Handshake.Event do
  @moduledoc """
  Event sent by ICE Source on its output pad after successful handshake.
  """

  @type t :: %__MODULE__{
          handshake_data: any()
        }
  defstruct handshake_data: nil
end

defimpl Membrane.EventProtocol, for: Membrane.ICE.Handshake.Event do
  @impl true
  def async?(_x), do: false

  @impl true
  def sticky?(_x), do: false
end
