defmodule Membrane.ICE.Support.TestSender do
  @moduledoc false

  use Membrane.Pipeline

  alias Membrane.Element.Hackney

  require Membrane.Logger

  @impl true
  def handle_init(opts) do
    children = %{
      sink: %Membrane.ICE.Sink{
        stun_servers: ["64.233.161.127:19302"],
        controlling_mode: true,
        handshake_module: opts[:handshake_module],
        handshake_opts: opts[:handshake_opts]
      }
    }

    spec = %ParentSpec{
      children: children
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_notification(
        {:component_state_ready, component_id, handshake_data},
        _from,
        _ctx,
        state
      ) do
    Membrane.Logger.debug("Handshake data #{inspect(handshake_data)}")

    children = %{
      source: %Hackney.Source{
        location: "https://membraneframework.github.io/static/video-samples/test-video.h264"
      }
    }

    pad = Pad.ref(:input, component_id)
    links = [link(:source) |> via_in(pad) |> to(:sink)]
    spec = %ParentSpec{children: children, links: links}
    {{:ok, spec: spec}, state}
  end

  @impl true
  def handle_notification(_other, _from, _ctx, state) do
    {:ok, state}
  end
end
