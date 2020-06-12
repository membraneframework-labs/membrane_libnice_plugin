defmodule Membrane.ICE.Agent.NativeTest do
  use ExUnit.Case
  alias Membrane.ICE.Agent.Native

  test "Native agent construction/destruction works" do
    ag = Native.create()
    assert is_reference(ag)
    Native.destroy(ag)
  end
end
