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
        controlling_mode: false
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
      sink: %File.Sink{
        location: "/tmp/ice-recv.h264"
      }
    }

    pad = Pad.ref(:output, state.ready_component)
    links = [link(:source) |> via_out(pad) |> to(:sink)]
    spec = %ParentSpec{children: children, links: links}
    {{:ok, spec: spec}, state}
  end

  @impl true
  def handle_notification({:stream_id, stream_id} = msg, _from, _ctx, state) do
    Membrane.Logger.info("#{inspect(msg)}")
    state = Map.put(state, :stream_id, stream_id)
    {{:ok, forward: {:source, :generate_local_sdp}}, state}
  end

  @impl true
  def handle_notification({:local_sdp, _sdp} = msg, _from, _ctx, state) do
    Membrane.Logger.info("#{inspect(msg)}")
    {{:ok, forward: {:source, {:gather_candidates, state.stream_id}}}, state}
  end

  @impl true
  def handle_notification(other, from, ctx, state) do
    Common.handle_notification(other, from, ctx, state)
  end

  @impl true
  def handle_other(:init, _ctx, state) do
    n_components = 1
    {{:ok, forward: {:source, {:add_stream, n_components}}}, state}
  end

  @impl true
  def handle_other({:set_remote_credentials, remote_credentials, stream_id}, _ctx, state) do
    {{:ok, forward: {:source, {:set_remote_credentials, remote_credentials, stream_id}}}, state}
  end

  @impl true
  def handle_other({:set_remote_candidate, candidate}, _ctx, state) do
    {{:ok, forward: {:source, {:set_remote_candidate, candidate, state.stream_id, 1}}}, state}
  end

  @impl true
  def handle_other(other, _ctx, state) do
    {{:ok, forward: {:source, other}}, state}
  end
end
