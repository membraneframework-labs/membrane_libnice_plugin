defmodule Membrane.ICE.Handshake.Event do
  @moduledoc """
  Event sent by ICE Sink and Source on Bin input and output pads after successful handshake.
  """
  @derive Membrane.EventProtocol

  @type t :: %__MODULE__{handshake_data: any()}
  defstruct handshake_data: nil
end
