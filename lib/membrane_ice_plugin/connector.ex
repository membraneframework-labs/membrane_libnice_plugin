defmodule Membrane.ICE.Connector do
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
            handshakes: handshakes(),
            handshake_module: Handshake.t(),
            handshake_opts: list(),
            connections: MapSet.t()
          }
    defstruct parent: nil,
              ice: nil,
              controlling_mode: false,
              stream_id: nil,
              n_components: 1,
              stream_name: "",
              handshakes: %{},
              handshake_module: Handshake.Default,
              handshake_opts: [],
              connections: MapSet.new()
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def get_ice_pid(pid) do
    GenServer.call(pid, :get_ice_pid)
  end

  def run(pid) do
    GenServer.call(pid, :run)
  end

  def generate_local_sdp(pid) do
    GenServer.call(pid, :generate_local_sdp)
  end

  def parse_remote_sdp(pid, sdp) do
    GenServer.call(pid, {:parse_remote_sdp, sdp})
  end

  def set_remote_credentials(pid, credentials) do
    GenServer.call(pid, {:set_remote_credentials, credentials})
  end

  def peer_candidate_gathering_done(pid) do
    GenServer.call(pid, :peer_candidate_gathering_done)
  end

  def set_remote_candidate(pid, candidate, component_id) do
    GenServer.call(pid, {:set_remote_candidate, candidate, component_id})
  end

  # Server API
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
      handshake_module: opts[:handshake_module],
      handshake_opts: opts[:handshake_opts]
    }

    {:ok, state}
  end

  def handle_call(:get_ice_pid, _from, %State{ice: ice} = state) do
    {:reply, {:ok, ice}, state}
  end

  def handle_call(:run, _from, %State{ice: ice} = state) do
    with {:ok, handshake_init_data, %State{stream_id: stream_id} = new_state} <-
           add_stream(state),
         {:ok, credentials} <- ExLibnice.get_local_credentials(ice, stream_id),
         :ok <- ExLibnice.gather_candidates(ice, stream_id) do
      {:reply, {:ok, handshake_init_data, credentials}, new_state}
    else
      {:error, cause} -> {:stop, {:error, cause}, state}
    end
  end

  def handle_call(:generate_local_sdp, _from, %State{ice: ice} = state) do
    {:ok, local_sdp} = ExLibnice.generate_local_sdp(ice)

    # the version of the SDP protocol. RFC 4566 defines only v=0 - section 5.1
    local_sdp = "v=0\r\n" <> local_sdp

    Membrane.Logger.debug("local sdp: #{inspect(local_sdp)}")

    {:reply, {:local_sdp, local_sdp}, state}
  end

  def handle_call({:parse_remote_sdp, sdp}, _from, %State{ice: ice} = state) do
    case ExLibnice.parse_remote_sdp(ice, sdp) do
      {:ok, added_cand_num} ->
        {:reply, {:parse_remote_sdp_ok, added_cand_num}, state}

      {:error, cause} ->
        {:reply, {:error, cause}, state}
    end
  end

  def handle_call(
        {:set_remote_credentials, credentials},
        _from,
        %{ice: ice, stream_id: stream_id} = state
      ) do
    case ExLibnice.set_remote_credentials(ice, credentials, stream_id) do
      :ok -> {:reply, :ok, state}
      {:error, cause} -> {:reply, {:error, cause}, state}
    end
  end

  def handle_call(
        :peer_candidate_gathering_done,
        _from,
        %State{ice: ice, stream_id: stream_id} = state
      ) do
    case ExLibnice.peer_candidate_gathering_done(ice, stream_id) do
      :ok -> {:reply, :ok, state}
      {:error, cause} -> {:reply, {:error, cause}, state}
    end
  end

  def handle_call(
        {:set_remote_candidate, candidate, component_id},
        _from,
        %State{ice: ice, stream_id: stream_id} = state
      ) do
    case ExLibnice.set_remote_candidate(ice, candidate, stream_id, component_id) do
      :ok -> {:reply, :ok, state}
      {:error, cause} -> {:reply, {:error, cause}, state}
    end
  end

  def handle_info({:new_candidate_full, _cand} = msg, %State{parent: parent} = state) do
    Membrane.Logger.debug("#{inspect(msg)}")
    send(parent, msg)
    {:noreply, state}
  end

  def handle_info({:new_remote_candidate_full, _cand} = msg, %State{parent: parent} = state) do
    Membrane.Logger.debug("#{inspect(msg)}")
    send(parent, msg)
    {:noreply, state}
  end

  def handle_info({:candidate_gathering_done, _stream_id} = msg, %State{parent: parent} = state) do
    Membrane.Logger.debug("#{inspect(msg)}")
    send(parent, :candidate_gathering_done)
    {:noreply, state}
  end

  def handle_info(
        {:new_selected_pair, _stream_id, component_id, lfoundation, rfoundation} = msg,
        %State{parent: parent} = state
      ) do
    Membrane.Logger.debug("#{inspect(msg)}")
    send(parent, {:new_selected_pair, component_id, lfoundation, rfoundation})
    {:noreply, state}
  end

  def handle_info({:component_state_failed, _stream_id, component_id}, state) do
    Membrane.Logger.warn("Component #{component_id} state FAILED")
    {:noreply, state}
  end

  def handle_info({:component_state_ready, stream_id, component_id}, state) do
    Membrane.Logger.debug("Component #{component_id} READY")

    %State{
      parent: parent,
      ice: ice,
      handshakes: handshakes,
      handshake_module: handshake_module
    } = state

    {handshake_state, handshake_status, handshake_data} = Map.get(handshakes, component_id)

    new_connections = MapSet.put(state.connections, component_id)
    new_state = %State{state | connections: new_connections}

    if handshake_status != :finished do
      res = handshake_module.connection_ready(handshake_state)

      {{finished?, handshake_data}, new_state} =
        parse_result(res, ice, stream_id, component_id, handshakes, handshake_state, new_state)

      if finished? do
        msg = {:component_ready, stream_id, component_id, handshake_data}
        send(parent, msg)
        {:noreply, new_state}
      else
        {:noreply, new_state}
      end
    else
      msg = {:component_ready, stream_id, component_id, handshake_data}
      send(parent, msg)
      {:noreply, new_state}
    end
  end

  def handle_info({:ice_payload, stream_id, component_id, payload}, state) do
    %State{
      parent: parent,
      ice: ice,
      handshakes: handshakes,
      handshake_module: handshake_module
    } = state

    {handshake_state, handshake_status, _handshake_data} = Map.get(handshakes, component_id)

    if handshake_status != :finished do
      res = handshake_module.recv_from_peer(handshake_state, payload)

      {{finished?, handshake_data}, new_state} =
        parse_result(res, ice, stream_id, component_id, handshakes, handshake_state, state)

      if finished? do
        send(parent, {:handshake_data, component_id, handshake_data})
      end

      if finished? and MapSet.member?(state.connections, component_id) do
        msg = {:component_ready, stream_id, component_id, handshake_data}
        send(parent, msg)
        {:noreply, new_state}
      else
        {:noreply, new_state}
      end
    else
      msg = {:ice_payload, component_id, payload}
      send(parent, msg)
      {:noreply, state}
    end
  end

  defp add_stream(state) do
    %State{
      ice: ice,
      n_components: n_components,
      stream_name: stream_name,
      handshake_module: handshake_module,
      handshake_opts: handshake_opts
    } = state

    case ExLibnice.add_stream(ice, n_components, stream_name) do
      {:ok, stream_id} ->
        handshake_init_results =
          1..n_components
          |> Map.new(&{&1, handshake_module.init(handshake_opts)})

        handshakes =
          1..n_components
          |> Map.new(fn component_id ->
            {component_id, parse_handshake_init_res(handshake_init_results[component_id])}
          end)

        handshake_init_data =
          1..n_components
          |> Map.new(fn component_id ->
            {_res, init_data, _state} = handshake_init_results[component_id]
            {component_id, init_data}
          end)

        new_state = %State{state | stream_id: stream_id, handshakes: handshakes}
        {:ok, handshake_init_data, new_state}

      {:error, cause} ->
        {:error, cause}
    end
  end

  defp parse_handshake_init_res({:ok, _init_data, state}), do: {state, :in_progress, nil}
  defp parse_handshake_init_res({:finished, _init_data}), do: {nil, :finished, nil}

  @spec parse_result(
          res ::
            :ok
            | {:finished_with_packets, handshake_data :: State.handshake_data(),
               packets :: binary()}
            | {:finished, handshake_data :: State.handshake_data()},
          ice :: pid(),
          stream_id :: non_neg_integer(),
          component_id :: State.component_id(),
          handshakes :: State.handshakes(),
          handshake_status :: State.handshake_status(),
          state :: State.t()
        ) ::
          {{finished? :: bool(), handshake_data :: State.handshake_data()},
           new_state :: State.t()}
  defp parse_result(res, ice, stream_id, component_id, handshakes, handshake_status, state) do
    case res do
      :ok ->
        {{false, nil}, state}

      {:ok, packets} ->
        ExLibnice.send_payload(ice, stream_id, component_id, packets)
        {{false, nil}, state}

      {:finished_with_packets, handshake_data, packets} ->
        ExLibnice.send_payload(ice, stream_id, component_id, packets)

        handshakes =
          Map.put(handshakes, component_id, {handshake_status, :finished, handshake_data})

        new_state = %State{state | handshakes: handshakes}
        {{true, handshake_data}, new_state}

      {:finished, handshake_data} ->
        handshakes =
          Map.put(handshakes, component_id, {handshake_status, :finished, handshake_data})

        new_state = %State{state | handshakes: handshakes}
        {{true, handshake_data}, new_state}
    end
  end
end
