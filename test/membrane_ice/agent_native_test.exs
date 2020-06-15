defmodule Membrane.ICE.Agent.NativeTest do
  use ExUnit.Case
  alias Membrane.ICE.Agent.Native

  test "Native agent construction/destruction works" do
    ag = Native.create(:rfc5245, [])
    assert is_reference(ag)
    Native.destroy(ag)
  end

  test "Native agent construction throws on invalid args" do
    assert_raise ErlangError, fn ->
      Native.create(:totally_not_working, [])
    end

    assert_raise ErlangError, fn ->
      Native.create(:rfc5245, [:ice_trickle, :totally_not_working])
    end
  end
end
