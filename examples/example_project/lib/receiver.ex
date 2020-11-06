defmodule Example.Receiver do
  use Membrane.Pipeline

  require Membrane.Logger

  alias Example.Common
  alias Membrane.Element.File

  @impl true
  def handle_init(_) do
    children = %{
      source: %Membrane.ICE.Source{
        stun_servers: ["64.233.161.127:19302"],
        controlling_mode: false,
        handshake_module: Membrane.DTLS.Handshake,
        handshake_opts: [client_mode: false, dtls_srtp: true]
      },
      sink: %File.Sink{
        location: "/tmp/ice-recv.h264"
      }
    }

    pad = Pad.ref(:output, 1)
    links = [link(:source) |> via_out(pad) |> to(:sink)]

    spec = %ParentSpec{
      children: children,
      links: links
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_notification({:local_sdp, _sdp} = msg, _from, _ctx, state) do
    Membrane.Logger.info("#{inspect(msg)}")
    {{:ok, forward: {:source, :gather_candidates}}, state}
  end

  @impl true
  def handle_notification(other, from, ctx, state) do
    Common.handle_notification(other, from, ctx, state)
  end

  @impl true
  def handle_other(:start, _ctx, state) do
    {{:ok, forward: {:source, :generate_local_sdp}}, state}
  end

  @impl true
  def handle_other({:set_remote_credentials, remote_credentials}, _ctx, state) do
    {{:ok, forward: {:source, {:set_remote_credentials, remote_credentials}}}, state}
  end

  @impl true
  def handle_other({:set_remote_candidate, candidate}, _ctx, state) do
    {{:ok, forward: {:source, {:set_remote_candidate, candidate, 1}}}, state}
  end

  @impl true
  def handle_other(other, _ctx, state) do
    {{:ok, forward: {:source, other}}, state}
  end
end
