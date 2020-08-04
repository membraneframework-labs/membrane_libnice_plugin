defmodule Membrane.Element.ICE.Sink do
  use Membrane.Sink

  require Unifex.CNode

  def_input_pad :input,
    availability: :on_request,
    caps: :any,
    mode: :pull,
    demand_unit: :buffers

  @impl true
  def handle_init(_options) do
    {:ok, cnode} = Unifex.CNode.start_link(:native)
    :ok = Unifex.CNode.call(cnode, :init)
    state = %{
      cnode: cnode
    }
    {:ok, state}
  end

  @impl true
  def handle_other(:gather_candidates, _context, %{cnode: cnode} = state) do
    Unifex.CNode.call(cnode, :gather_candidates)
    {:ok, state}
  end

  @impl true
  def handle_other({:new_candidate_full, _ip} = candidate, _context, state) do
    {{:ok, notify: candidate}, state}
  end

  @impl true
  def handle_other({:candidate_gathering_done}, _context, state) do
    {{:ok, notify: :gathering_done}, state}
  end
end
