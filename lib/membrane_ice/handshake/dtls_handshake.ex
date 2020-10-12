defmodule Membrane.ICE.Handshake.DTLS do
  @moduledoc """
  Module responsible for performing DTLS and DTLS-SRTP handshake.

  As `handshake_opts` in Sink/Source there should be passed keyword list containing following
  fields:
  * client_mode :: boolean()
  * dtls_srtp :: boolean()

  Please refer to `ExDTLS` library documentation for meaning of these fields.
  """
  @behaviour Membrane.ICE.Handshake

  use GenServer

  alias Membrane.ICE.Handshake

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
        client_mode: opts[:client_mode],
        dtls_srtp: opts[:dtls_srtp]
      )

    {:ok, %{:dtls => dtls}}
  end

  @impl GenServer
  def handle_call(:connection_ready, _from, %{dtls: dtls} = state) do
    {:ok, packets} = ExDTLS.do_handshake(dtls)
    {:reply, {:ok, packets}, state}
  end

  @impl GenServer
  def handle_call({:recv_from_peer, data}, _from, %{dtls: dtls} = state) do
    msg = ExDTLS.do_handshake(dtls, data)
    {:reply, msg, state}
  end
end
