defmodule Membrane.Element.ICE do
  require Unifex.CNode

  def gather_candidates() do
    {:ok, cnode} = Unifex.CNode.start_link(:native)
    {:ok} = Unifex.CNode.call(cnode, :init, [])
    Unifex.CNode.call(cnode, :start_gathering_candidates, [])
    receive_candidates()
  end

  defp receive_candidates() do
    receive do
      {:gathering_done} ->
        IO.inspect("Gathering done")

      candidate ->
        IO.inspect(candidate)
        receive_candidates()
    end
  end
end
