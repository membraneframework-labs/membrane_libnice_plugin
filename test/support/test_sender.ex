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
      },
      source: %Hackney.Source{
        location: "https://membraneframework.github.io/static/video-samples/test-video.h264"
      }
    }

    pad = Pad.ref(:input, 1)
    links = [link(:source) |> via_in(pad) |> to(:sink)]
    spec = %ParentSpec{children: children, links: links}
    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_notification(_other, _from, _ctx, state) do
    {:ok, state}
  end
end
