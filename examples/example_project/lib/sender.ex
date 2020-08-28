defmodule Example.Sender do
  use Membrane.Pipeline

  alias Membrane.Element.File

  require Membrane.Logger

  @impl true
  def handle_init(_) do
    children = %{
      sink: %Membrane.ICE.Sink{
        stun_servers: ['64.233.161.127:19302'],
        controlling_mode: 1
      }
    }

    spec = %ParentSpec{
      children: children
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_stopped_to_prepared(_ctx, state) do
    n_components = 1
    {{:ok, forward: {:sink, {:add_stream, n_components}}}, state}
  end

  @impl true
  def handle_notification({:stream_id, stream_id}, _from, _ctx, state) do
    state = Map.put(state, :stream_id, stream_id)
    {{:ok, forward: {:sink, {:gather_candidates, stream_id}}}, state}
  end

  @impl true
  def handle_notification({:new_candidate_full, _candidate}, _from, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_notification({:candidate_gathering_done, stream_id}, _from, _ctx, state) do
    {{:ok, forward: {:sink, {:get_local_credentials, stream_id}}}, state}
  end

  @impl true
  def handle_notification({:local_credentials, _credentials}, _from, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_notification(
        {:new_selected_pair, _stream_id, _component_id, _lfoundation, _rfoundation},
        _from,
        _ctx,
        state
      ) do
    {:ok, state}
  end

  @impl true
  def handle_notification({:component_state_ready, stream_id, component_id}, _from, _ctx, state) do
    children = %{
      source: %File.Source{
        location: "~/Videos/test-video.h264"
      }
    }

    pad = Pad.ref(:input, {stream_id, component_id})
    links = [link(:source) |> via_in(pad) |> to(:sink)]
    spec = %ParentSpec{children: children, links: links}
    {{:ok, spec: spec}, state}
  end

  @impl true
  def handle_notification(notification, from, _ctx, state) do
    Membrane.Logger.warn("other notification: #{inspect(notification)}} from: #{inspect(from)}")

    {:ok, state}
  end

  @impl true
  def handle_other({:set_remote_credentials, remote_credentials, stream_id}, _ctx, state) do
    {{:ok, forward: {:sink, {:set_remote_credentials, remote_credentials, stream_id}}}, state}
  end

  @impl true
  def handle_other({:set_remote_candidate, candidate}, _ctx, state) do
    {{:ok, forward: {:sink, {:set_remote_candidate, candidate, state.stream_id, 1}}}, state}
  end

  @impl true
  def handle_other(msg, _ctx, state) do
    Membrane.Logger.warn("unknown message: #{inspect(msg)}")

    {:ok, state}
  end
end
