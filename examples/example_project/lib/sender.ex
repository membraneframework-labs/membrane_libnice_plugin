defmodule Example.Sender do
  use Membrane.Pipeline

  require Membrane.Logger

  alias Example.Common
  alias Membrane.Element.Hackney

  @impl true
  def handle_init(_) do
    children = %{
      sink: %Membrane.ICE.Sink{
        stream_name: "audio",
        stun_servers: ["64.233.161.127:19302"],
        controlling_mode: true,
        handshake_module: Membrane.DTLS.Handshake,
        handshake_opts: [client_mode: true, dtls_srtp: true]
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
  def handle_notification({:local_sdp, _sdp} = msg, _from, _ctx, state) do
    Membrane.Logger.info("#{inspect(msg)}")
    {{:ok, forward: {:sink, :gather_candidates}}, state}
  end

  @impl true
  def handle_notification(other, from, ctx, state) do
    Common.handle_notification(other, from, ctx, state)
  end

  @impl true
  def handle_other(:start, _ctx, state) do
    {{:ok, forward: {:sink, :generate_local_sdp}}, state}
  end

  @impl true
  def handle_other({:set_remote_credentials, remote_credentials}, _ctx, state) do
    {{:ok, forward: {:sink, {:set_remote_credentials, remote_credentials}}}, state}
  end

  @impl true
  def handle_other({:set_remote_candidate, candidate}, _ctx, state) do
    {{:ok, forward: {:sink, {:set_remote_candidate, candidate, 1}}}, state}
  end

  @impl true
  def handle_other(other, _ctx, state) do
    {{:ok, forward: {:sink, other}}, state}
  end
end
