defmodule Example.Pipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_) do
    children = %{
      sink: Membrane.Element.ICE.Sink
    }

    spec = %ParentSpec{
      children: children,
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_notification(notification, from, state) do
    IO.inspect("got notification #{inspect(notification)} from #{from} ")
    {:ok, state}
  end

  @impl true
  def handle_stopped_to_prepared(state) do
    {{:ok, forward: {:sink, :start_gathering_candidates}}, state}
  end

end
