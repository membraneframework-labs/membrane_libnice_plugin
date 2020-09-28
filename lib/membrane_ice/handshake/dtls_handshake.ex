defmodule Handshake.DTLS do
  use GenServer

  @behaviour Handshake

  require Membrane.Logger

  # Client API
  @impl Handshake
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl Handshake
  def connection_ready(pid, stream_id, component_id) do
    GenServer.call(pid, {:connection_ready, stream_id, component_id})
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

    {:ok, %{:parent => opts[:parent], :dtls => dtls, ice: opts[:ice]}}
  end

  @impl GenServer
  def handle_call({:connection_ready, stream_id, component_id}, _from, %{dtls: dtls} = state) do
    :ok = ExDTLS.do_handshake(dtls)
    new_state = Map.put(state, :stream_id, stream_id)
    new_state = Map.put(new_state, :component_id, component_id)
    {:reply, :ok, new_state}
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
  def handle_info({:handshake_finished, _keying_material} = msg, %{parent: parent} = state) do
    send(parent, msg)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(msg, state) do
    Membrane.Logger.debug("Unknown msg: #{inspect(msg)}, #{inspect(state)}")
    {:noreply, state}
  end
end
