defmodule Membrane.ICE.Connector do
  @moduledoc false

  # This module is responsible for interacting with `libnice` i.e. establishing connection,
  # sending and receiving messages and conveying them to ICE Bin.

  use GenServer

  alias Membrane.ICE.Handshake

  require Unifex.CNode
  require Membrane.Logger

  defmodule State do
    @moduledoc false

    @type handshake_status :: :in_progress | :finished
    @type handshake_data :: term()
    @type component_id :: non_neg_integer()
    @type handshakes :: %{
            component_id() => {Handshake.state(), handshake_status(), handshake_data()}
          }

    @type t :: %__MODULE__{
            parent: pid(),
            ice: pid(),
            controlling_mode: boolean(),
            stream_id: integer(),
            n_components: integer(),
            stream_name: String.t(),
            turn_servers: [ExLibnice.relay_info()],
            handshakes: handshakes(),
            hsk_module: Handshake.t(),
            hsk_opts: list(),
            connections: MapSet.t(),
            cached_hsk_packets: %{key: component_id(), value: binary()}
          }
    defstruct parent: nil,
              ice: nil,
              controlling_mode: false,
              stream_id: nil,
              n_components: 1,
              stream_name: "",
              turn_servers: [],
              handshakes: %{},
              hsk_module: Handshake.Default,
              hsk_opts: [],
              connections: MapSet.new(),
              cached_hsk_packets: %{}
  end

  @spec start_link(opts :: keyword()) :: {:ok, pid()}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec get_ice_pid(connector :: pid()) :: {:ok, ice_pid :: pid()}
  def get_ice_pid(pid) do
    GenServer.call(pid, :get_ice_pid)
  end

  @spec run(connector :: pid()) ::
          {:ok, hsk_init_data :: Handshake.init_notification(), credentials :: String.t()}
  def run(pid) do
    GenServer.call(pid, :run)
  end

  @spec gather_candidates(connector :: pid()) :: :ok
  def gather_candidates(pid) do
    GenServer.cast(pid, :gather_candidates)
  end

  @spec generate_local_sdp(connector :: pid()) :: {:ok, local_sdp :: String.t()}
  def generate_local_sdp(pid) do
    GenServer.call(pid, :generate_local_sdp)
  end

  @spec parse_remote_sdp(connector :: pid(), sdp :: String.t()) :: :ok
  def parse_remote_sdp(pid, sdp) do
    GenServer.call(pid, {:parse_remote_sdp, sdp})
  end

  @spec set_remote_credentials(connector :: pid(), credentials :: String.t()) :: :ok
  def set_remote_credentials(pid, credentials) do
    GenServer.call(pid, {:set_remote_credentials, credentials})
  end

  @spec peer_candidate_gathering_done(connector :: pid()) :: :ok
  def peer_candidate_gathering_done(pid) do
    GenServer.call(pid, :peer_candidate_gathering_done)
  end

  @spec set_remote_candidate(
          connector :: pid(),
          candidate :: String.t(),
          component_id :: non_neg_integer()
        ) :: :ok
  def set_remote_candidate(pid, candidate, component_id) do
    GenServer.call(pid, {:set_remote_candidate, candidate, component_id})
  end

  @spec restart_stream(connector :: pid()) :: {:ok, credentials: String.t()}
  def restart_stream(pid) do
    GenServer.call(pid, :restart_stream)
  end

  @spec reset(connector :: pid()) :: :ok
  def reset(pid) do
    GenServer.call(pid, :reset)
  end

  # Server API
  @impl true
  def init(opts) do
    {:ok, ice} =
      ExLibnice.start_link(
        parent: self(),
        stun_servers: opts[:stun_servers],
        controlling_mode: opts[:controlling_mode],
        port_range: opts[:port_range]
      )

    state = %State{
      parent: opts[:parent],
      ice: ice,
      controlling_mode: opts[:controlling_mode],
      n_components: opts[:n_components],
      stream_name: opts[:stream_name],
      turn_servers: opts[:turn_servers],
      hsk_module: opts[:hsk_module],
      hsk_opts: opts[:hsk_opts]
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_ice_pid, _from, %State{ice: ice} = state) do
    {:reply, {:ok, ice}, state}
  end

  @impl true
  def handle_call(:run, _from, %State{ice: ice} = state) do
    with {:ok, hsk_init_data, %State{stream_id: stream_id} = state} <-
           add_stream(state),
         :ok <- ExLibnice.set_relay_info(ice, stream_id, :all, []),
         {:ok, credentials} <- ExLibnice.get_local_credentials(ice, stream_id) do
      {:reply, {:ok, hsk_init_data, credentials}, state}
    else
      {:error, cause} -> {:stop, {:error, cause}, state}
    end
  end

  @impl true
  def handle_call(:generate_local_sdp, _from, %State{ice: ice} = state) do
    {:ok, local_sdp} = ExLibnice.generate_local_sdp(ice)
    # the version of the SDP protocol. RFC 4566 defines only v=0 - section 5.1
    local_sdp = "v=0\r\n" <> local_sdp
    {:reply, {:ok, local_sdp}, state}
  end

  @impl true
  def handle_call({:parse_remote_sdp, sdp}, _from, %State{ice: ice} = state) do
    ExLibnice.parse_remote_sdp(ice, sdp)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(
        {:set_remote_credentials, credentials},
        _from,
        %{ice: ice, stream_id: stream_id} = state
      ) do
    ExLibnice.set_remote_credentials(ice, credentials, stream_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(
        :peer_candidate_gathering_done,
        _from,
        %State{ice: ice, stream_id: stream_id} = state
      ) do
    ExLibnice.peer_candidate_gathering_done(ice, stream_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(
        {:set_remote_candidate, candidate, component_id},
        _from,
        %State{ice: ice, stream_id: stream_id} = state
      ) do
    ExLibnice.set_remote_candidate(ice, candidate, stream_id, component_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:restart_stream, _from, %State{ice: ice, stream_id: stream_id} = state) do
    with :ok <- ExLibnice.restart_stream(ice, stream_id),
         {:ok, credentials} <- ExLibnice.get_local_credentials(ice, stream_id),
         :ok <- ExLibnice.gather_candidates(ice, stream_id) do
      {:reply, {:ok, credentials}, state}
    else
      {:error, cause} -> {:reply, {:error, cause}, state}
    end
  end

  @impl true
  def handle_call(:reset, _from, %State{ice: ice, stream_id: stream_id} = state) do
    ExLibnice.remove_stream(ice, stream_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(:gather_candidates, %State{ice: ice, stream_id: stream_id} = state) do
    ExLibnice.gather_candidates(ice, stream_id)
    {:noreply, state}
  end

  @impl true
  def handle_info({:new_candidate_full, _cand} = msg, %State{parent: parent} = state) do
    send(parent, msg)
    {:noreply, state}
  end

  @impl true
  def handle_info({:new_remote_candidate_full, _cand} = msg, %State{parent: parent} = state) do
    send(parent, msg)
    {:noreply, state}
  end

  @impl true
  def handle_info({:candidate_gathering_done, _stream_id}, %State{parent: parent} = state) do
    send(parent, :candidate_gathering_done)
    {:noreply, state}
  end

  @impl true
  def handle_info({:new_selected_pair, _stream_id, _component_id, _lf, _rf}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:component_state_failed, stream_id, component_id}, state) do
    Membrane.Logger.warn("Component #{component_id} state FAILED")
    send(state.parent, {:component_state_failed, stream_id, component_id})
    {:noreply, state}
  end

  @impl true
  def handle_info({:component_state_ready, stream_id, component_id, _port} = msg, state) do
    Membrane.Logger.debug("Component #{component_id} READY")

    {hsk_state, hsk_status, _hsk_data} = Map.get(state.handshakes, component_id)

    if MapSet.member?(state.connections, component_id) and hsk_status != :finished do
      send(state.parent, {:component_state_failed, stream_id, component_id})
      {:noreply, state}
    else
      state = %{state | connections: MapSet.put(state.connections, component_id)}

      if hsk_status == :finished do
        send(state.parent, {:connection_ready, stream_id, component_id})
      else
        Membrane.Logger.debug("Checking for cached handshake packets")
        {cached_packets, state} = pop_in(state.cached_hsk_packets[component_id])

        if cached_packets == nil do
          Membrane.Logger.debug("Nothing to be sent for component: #{component_id}")
        else
          Membrane.Logger.debug("Sending cached handshake packets for component: #{component_id}")
          ExLibnice.send_payload(state.ice, stream_id, component_id, cached_packets)
        end

        handle_connection_ready(state.hsk_module.connection_ready(hsk_state), component_id, state)
      end

      send(state.parent, msg)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:ice_payload, _stream_id, component_id, payload}, state) do
    {hsk_state, _hsk_status, _hsk_data} = Map.get(state.handshakes, component_id)

    if state.hsk_module.is_hsk_packet(payload, hsk_state) do
      handle_process(state.hsk_module.process(payload, hsk_state), component_id, state)
    else
      send(state.parent, {:ice_payload, component_id, payload})
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:retransmit, from, packets}, state) do
    for {component_id, {%{dtls: dtls_pid}, _hsk_status, _hsk_data}} <- state.handshakes,
        dtls_pid == from do
      ExLibnice.send_payload(state.ice, state.stream_id, component_id, packets)
    end

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %State{ice: ice, hsk_module: hsk_module, handshakes: handshakes}) do
    handshakes
    |> Map.values()
    |> Enum.each(fn {state, _status, _data} -> hsk_module.stop(state) end)

    GenServer.stop(ice)
  end

  defp handle_connection_ready(:ok, _component_id, _state), do: :ok

  defp handle_connection_ready({:ok, packets}, component_id, state) do
    ExLibnice.send_payload(state.ice, state.stream_id, component_id, packets)
    :ok
  end

  defp handle_process(:ok, _component_id, state) do
    {:noreply, state}
  end

  defp handle_process({:ok, _packets}, _component_id, state) do
    Membrane.Logger.warn("Got regular handshake packet. Ignoring for now.")
    {:noreply, state}
  end

  defp handle_process({:handshake_packets, packets}, component_id, state) do
    if MapSet.member?(state.connections, component_id) do
      ExLibnice.send_payload(state.ice, state.stream_id, component_id, packets)
      {:noreply, state}
    else
      # if connection is not ready yet cache data
      # TODO maybe try to send?
      state = put_in(state.cached_hsk_packets[component_id], packets)
      {:noreply, state}
    end
  end

  defp handle_process({:handshake_finished, hsk_data}, component_id, state),
    do: handle_end_of_hsk(component_id, hsk_data, state)

  defp handle_process({:handshake_finished, hsk_data, packets}, component_id, state) do
    ExLibnice.send_payload(state.ice, state.stream_id, component_id, packets)
    handle_end_of_hsk(component_id, hsk_data, state)
  end

  defp handle_process({:connection_closed, reason}, _component_id, state) do
    Membrane.Logger.debug("Connection closed, reason: #{inspect(reason)}. Ignoring for now.")
    {:noreply, state}
  end

  defp handle_end_of_hsk(component_id, hsk_data, state) do
    {hsk_state, _hsk_status, _hsk_data} = Map.get(state.handshakes, component_id)
    state = put_in(state.handshakes[component_id], {hsk_state, :finished, hsk_data})
    send(state.parent, {:hsk_finished, component_id, hsk_data})

    if MapSet.member?(state.connections, component_id) do
      send(state.parent, {:connection_ready, state.stream_id, component_id})
    end

    {:noreply, state}
  end

  defp add_stream(state) do
    %State{
      ice: ice,
      n_components: n_components,
      stream_name: stream_name,
      hsk_module: hsk_module,
      hsk_opts: hsk_opts
    } = state

    case ExLibnice.add_stream(ice, n_components, stream_name) do
      {:ok, stream_id} ->
        hsk_init_results =
          1..n_components
          |> Map.new(&{&1, hsk_module.init(&1, self(), hsk_opts)})

        handshakes =
          1..n_components
          |> Map.new(&{&1, parse_handshake_init_res(hsk_init_results[&1], &1, state)})

        hsk_init_data =
          1..n_components
          |> Map.new(&{&1, get_init_data_from_init_result(hsk_init_results[&1])})

        state = %State{state | stream_id: stream_id, handshakes: handshakes}
        {:ok, hsk_init_data, state}

      {:error, cause} ->
        {:error, cause}
    end
  end

  defp parse_handshake_init_res({:ok, _init_data, hsk_state}, _component_id, _state),
    do: {hsk_state, :in_progress, nil}

  defp parse_handshake_init_res({:finished, _init_data}, component_id, state) do
    send(state.parent, {:hsk_finished, component_id, nil})
    {nil, :finished, nil}
  end

  defp get_init_data_from_init_result({:ok, init_data, _state}), do: init_data
  defp get_init_data_from_init_result({:finished, init_data}), do: init_data
end
