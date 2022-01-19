defmodule Membrane.Libnice.Support.TestReceiver do
  @moduledoc false

  use Membrane.Pipeline

  alias Membrane.File

  require Membrane.Logger

  @impl true
  def handle_init(opts) do
    children = %{
      ice: %Membrane.Libnice.Bin{
        stun_servers: [%{server_addr: "stun1.l.google.com", server_port: 19_302}],
        controlling_mode: false,
        handshake_module: opts[:handshake_module],
        handshake_opts: opts[:handshake_opts]
      },
      sink: %File.Sink{
        location: opts[:file_path]
      }
    }

    pad = Pad.ref(:output, 1)
    links = [link(:ice) |> via_out(pad) |> to(:sink)]

    spec = %ParentSpec{
      children: children,
      links: links
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    {{:ok, forward: [ice: :gather_candidates]}, state}
  end
end
