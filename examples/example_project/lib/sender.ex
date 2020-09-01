defmodule Example.Sender do
  use Membrane.Pipeline

  require Membrane.Logger

  alias Example.Common
  alias Membrane.Element.Hackney

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
  def handle_prepared_to_playing(_ctx, state) do
    children = %{
      source: %Hackney.Source{
        location: "https://membraneframework.github.io/static/video-samples/test-video.h264"
      }
    }

    pad = Pad.ref(:input, state.ready_component)
    links = [link(:source) |> via_in(pad) |> to(:sink)]
    spec = %ParentSpec{children: children, links: links}
    {{:ok, spec: spec}, state}
  end

  @impl true
  def handle_notification({:stream_id, stream_id} = msg, _from, _ctx, state) do
    Membrane.Logger.info("#{inspect(msg)}")

    state = Map.put(state, :stream_id, stream_id)
    {{:ok, forward: {:sink, {:gather_candidates, stream_id}}}, state}
  end

  @impl true
  def handle_notification({:candidate_gathering_done, stream_id}, _from, _ctx, state) do
    {{:ok, forward: {:sink, {:get_local_credentials, stream_id}}}, state}
  end

  @impl true
  def handle_notification(other, from, ctx, state) do
    Common.handle_notification(other, from, ctx, state)
  end

  @impl true
  def handle_other(:init, _ctx, state) do
    n_components = 1
    {{:ok, forward: {:sink, {:add_stream, n_components}}}, state}
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
  def handle_other(other, _ctx, state) do
    {{:ok, forward: {:source, other}}, state}
  end
end
