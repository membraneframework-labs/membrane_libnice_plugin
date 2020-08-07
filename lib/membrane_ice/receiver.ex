defmodule Example.Receiver do
  use Membrane.Pipeline

  alias Membrane.Element.File

  @impl true
  def handle_init(_) do
    children = %{
      source: Membrane.Element.ICE.Source,
      sink: %File.Sink{
        location: "/tmp/udp-recv.h264"
      }
    }

    links = [
      link(:source) |> to(:sink)
    ]

    spec = %ParentSpec{
      children: children,
      links: links
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_notification({:stream_id, stream_id}, from, state) do
    IO.inspect("pipeline got notification #{inspect(stream_id)} from #{from} ")
    state = Map.put(state, :stream_id, stream_id)
    {{:ok, forward: {:source, {:gather_candidates, stream_id}}}, state}
  end

  @impl true
  def handle_notification({:local_credentials, credentials}, from, state) do
    IO.inspect("pipeline got notification #{inspect(credentials)} from #{from} ")
    {:ok, state}
  end

  @impl true
  def handle_notification({:set_remote_credentials, remote_credentials, stream_id}, from, state) do
    IO.inspect("pipeline got notification #{inspect(remote_credentials)} from #{from} ")
    {{:ok, forward: {:source, {:set_remote_credentials, remote_credentials, stream_id}}}, state}
  end

  @impl true
  def handle_notification({:set_remote_candidate, candidate}, _context, state) do
    {{:ok, forward: {:source, {:set_remote_candidate, candidate, state.stream_id, 1}}}, state}
  end

  @impl true
  def handle_notification({:new_candidate_full, candidates}, from, state) do
    IO.inspect("pipeline got new candidate full #{inspect(candidates)} from #{from} ")
    {:ok, state}
  end

  @impl true
  def handle_notification(:gathering_done, from, state) do
    IO.inspect("pipeline got notification :gathering_done from #{from}")
    {{:ok, forward: {:source, {:get_local_credentials, state.stream_id}}}, state}
  end

  @impl true
  def handle_stopped_to_prepared(state) do
    n_components = 1
    {{:ok, forward: {:source, {:add_stream, n_components}}}, state}
  end

  @impl true
  def handle_other({:set_remote_credentials, remote_credentials, stream_id}, state) do
    IO.inspect("pipeline got other msg #{inspect(remote_credentials)}")
    {{:ok, forward: {:source, {:set_remote_credentials, remote_credentials, stream_id}}}, state}
  end

  @impl true
  def handle_other({:set_remote_candidate, candidate}, state) do
    IO.inspect("pipeline got other msg #{inspect(candidate)}")
    {{:ok, forward: {:source, {:set_remote_candidate, candidate, state.stream_id, 1}}}, state}
  end
end
