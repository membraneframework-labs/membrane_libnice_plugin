defmodule Membrane.Libnice.Handshake.Event do
  @moduledoc """
  Event sent by Libnice Sink and Source on Bin input and output pads after successful handshake.
  """
  @derive Membrane.EventProtocol

  @type t :: %__MODULE__{handshake_data: any()}
  defstruct handshake_data: nil
end
