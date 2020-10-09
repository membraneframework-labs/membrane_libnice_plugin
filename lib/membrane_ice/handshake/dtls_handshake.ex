defmodule Membrane.ICE.Handshake.DTLS do
  @moduledoc """
  Module responsible for performing DTLS and DTLS-SRTP handshake.

  As `handshake_opts` in Sink/Source there should be passed keyword list containing following
  fields:
  * client_mode :: boolean()
  * dtls_srtp :: boolean()

  Please refer to `ExDTLS` library documentation for meaning of these fields.
  """
  use GenServer

  alias Membrane.ICE.Handshake

  @behaviour Handshake

  require Membrane.Logger

  # Client API
  @impl Handshake
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl Handshake
  def connection_ready(pid) do
    GenServer.call(pid, :connection_ready)
  end

  @impl Handshake
  def recv_from_peer(pid, data) do
    GenServer.call(pid, {:recv_from_peer, data})
  end

  # Server API
  @impl GenServer
  def init(opts) do
    {:ok, dtls} =
      ExDTLS.start_link(
        parent: self(),
        client_mode: opts[:client_mode],
        dtls_srtp: opts[:dtls_srtp]
      )

    {:ok,
     %{
       :parent => opts[:parent],
       :dtls => dtls,
       :ice => opts[:ice],
       :stream_id => opts[:stream_id],
       :component_id => opts[:component_id]
     }}
  end

  @impl GenServer
  def handle_call(:connection_ready, _from, %{dtls: dtls} = state) do
    :ok = ExDTLS.do_handshake(dtls)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:recv_from_peer, data}, _from, %{dtls: dtls} = state) do
    :ok = ExDTLS.feed(dtls, data)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(
        {:packets, payload},
        %{ice: ice, stream_id: stream_id, component_id: component_id} = state
      ) do
    Membrane.Logger.debug("Send payload #{inspect(payload)}")
    :ok = ExLibnice.send_payload(ice, stream_id, component_id, payload)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        {:handshake_finished, keying_material},
        %{parent: parent, component_id: component_id} = state
      ) do
    send(parent, {:handshake_finished, component_id, keying_material})
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(msg, state) do
    Membrane.Logger.debug("Unknown msg: #{inspect(msg)}")
    {:noreply, state}
  end
end
