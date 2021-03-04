defmodule Membrane.ICE.Support.TestReceiver do
  @moduledoc false

  use Membrane.Pipeline

  alias Membrane.File

  require Membrane.Logger

  @impl true
  def handle_init(opts) do
    children = %{
      ice: %Membrane.ICE.Bin{
        stun_servers: ["64.233.161.127:19302"],
        controlling_mode: false,
        hsk_module: opts[:hsk_module],
        hsk_opts: opts[:hsk_opts]
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
end
