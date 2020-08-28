defmodule Membrane.ICE.Support.TestSender do
  use Membrane.Pipeline

  alias Membrane.Element.Hackney

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
  def handle_prepared_to_playing(_ctx, state) do
    children = %{
      source: %Hackney.Source{
        location: "https://membraneframework.github.io/static/video-samples/test-video.h264"
      }
    }

    pad = Pad.ref(:input, {state.stream_id, state.component_id})
    links = [link(:source) |> via_in(pad) |> to(:sink)]
    spec = %ParentSpec{children: children, links: links}
    {{:ok, spec: spec}, state}
  end

  @impl true
  def handle_notification({:component_state_ready, stream_id, component_id}, _from, _ctx, _state) do
    new_state = %{:stream_id => stream_id, :component_id => component_id}
    {:ok, new_state}
  end

  @impl true
  def handle_notification(_other, _from, _ctx, state) do
    {:ok, state}
  end
end
