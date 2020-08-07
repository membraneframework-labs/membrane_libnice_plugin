defmodule Example.Pipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_) do
    children = %{
      sink: Membrane.Element.ICE.Sink
    }

    spec = %ParentSpec{
      children: children
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_notification({:stream_id, stream_id}, from, state) do
    IO.inspect("pipeline got notification #{inspect(stream_id)} from #{from} ")
    {{:ok, forward: {:sink, {:gather_candidates, stream_id}}}, state}
  end

  @impl true
  def handle_notification({:local_credentials, credentials}, from, state) do
    IO.inspect("pipeline got notification #{inspect(credentials)} from #{from} ")
    {{:ok, forward: {:sink, {:set_remote_credentials, credentials, 1}}}, state}
  end

  @impl true
  def handle_notification({:new_candidate_full, candidates}, from, state) do
    IO.inspect("pipeline got notification #{inspect(candidates)} from #{from} ")
    {{:ok, forward: {:sink, {:set_remote_candidate, candidates, 1, 1}}}, state}
  end

  @impl true
  def handle_notification(notification, from, state) do
    IO.inspect("pipeline got notification #{inspect(notification)} from #{from} ")
    {:ok, state}
  end

  @impl true
  def handle_stopped_to_prepared(state) do
    n_components = 1
    {{:ok, forward: {:sink, {:add_stream, n_components}}}, state}
  end
end
