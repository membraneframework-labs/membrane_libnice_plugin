defmodule Membrane.ICE.Common do
  @moduledoc false

  # Module containing common behaviour for Sink and Source modules.

  alias Membrane.ICE.Handshake
  alias Membrane.Element.CallbackContext.PlaybackChange
  alias Membrane.Element.CallbackContext.Other
  alias Membrane.Element.Base
  alias Membrane.Pad

  require Unifex.CNode
  require Membrane.Logger
  require Membrane.Pad

  defmodule State do
    @moduledoc false

    @type handshake_status :: :in_progress | :finished
    @type handshake_data :: term()
    @type component_id :: non_neg_integer()
    @type handshakes :: %{
            component_id() => {Handshake.state(), handshake_status(), handshake_data()}
          }

    @type t :: %__MODULE__{
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
    defstruct ice: nil,
              controlling_mode: false,
              stream_id: nil,
              n_components: 1,
              stream_name: "",
              handshakes: %{},
              handshake_module: Handshake.Default,
              handshake_opts: [],
              connections: MapSet.new()
  end

  @spec handle_prepared_to_playing(
          ctx :: PlaybackChange.t(),
          state :: State.t(),
          pads_type :: :input | :output
        ) ::
          Base.callback_return_t()
  def handle_prepared_to_playing(ctx, %State{ice: ice} = state, pads_type) do
    unlinked_components =
      Enum.reject(1..state.n_components, &Map.has_key?(ctx.pads, Pad.ref(pads_type, &1)))

    if Enum.empty?(unlinked_components) do
      with {:ok, %State{stream_id: stream_id} = new_state} <- add_stream(state),
           {:ok, credentials} <- ExLibnice.get_local_credentials(ice, stream_id),
           :ok <- ExLibnice.gather_candidates(ice, stream_id) do
        {{:ok, notify: {:local_credentials, credentials}}, new_state}
      else
        {:error, cause} -> {{:error, cause}, state}
      end
    else
      {{:error,
        "Pads for components no. #{Enum.join(unlinked_components, ", ")} haven't been linked"},
       state}
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
        handshakes =
          1..n_components
          |> Map.new(&{&1, parse_handshake_init_res(handshake_module.init(handshake_opts))})

        new_state = %State{state | stream_id: stream_id, handshakes: handshakes}
        {:ok, new_state}

      {:error, cause} ->
        {:error, cause}
    end
  end

  defp parse_handshake_init_res({:ok, ctx}), do: {ctx, :in_progress, nil}
  defp parse_handshake_init_res(:finished), do: {nil, :finished, nil}

  @spec handle_ice_message(
          :generate_local_sdp
          | {:parse_remote_sdp, sdp :: String.t()}
          | {:set_remote_credentials, credentials :: String.t()}
          | :peer_candidate_gathering_done
          | {:set_remote_candidate, candidate :: String.t(), component_id :: non_neg_integer()}
          | {:new_candidate_full, cand :: String.t()}
          | {:candidate_gathering_done, stream_id :: non_neg_integer()}
          | {:new_selected_pair, stream_id :: non_neg_integer(),
             component_id :: non_neg_integer(), lfoundation :: String.t(),
             rfoundation :: String.t()}
          | {:new_remote_candidate_full, cand :: String.t()}
          | {:component_state_failed, stream_id :: non_neg_integer(),
             component_id :: non_neg_integer()}
          | any(),
          ctx :: PlaybackChange.t() | Other.t(),
          state :: State.t()
        ) ::
          Base.callback_return_t()
  def handle_ice_message(:generate_local_sdp, _ctx, %State{ice: ice} = state) do
    {:ok, local_sdp} = ExLibnice.generate_local_sdp(ice)

    # the version of the SDP protocol. RFC 4566 defines only v=0 - section 5.1
    local_sdp = "v=0\r\n" <> local_sdp

    Membrane.Logger.debug("local sdp: #{inspect(local_sdp)}")

    {{:ok, notify: {:local_sdp, local_sdp}}, state}
  end

  def handle_ice_message({:parse_remote_sdp, sdp}, _ctx, %State{ice: ice} = state) do
    case ExLibnice.parse_remote_sdp(ice, sdp) do
      {:ok, added_cand_num} ->
        {{:ok, notify: {:parse_remote_sdp_ok, added_cand_num}}, state}

      {:error, cause} ->
        {{:error, cause}, state}
    end
  end

  def handle_ice_message(
        {:set_remote_credentials, credentials},
        _ctx,
        %{ice: ice, stream_id: stream_id} = state
      ) do
    result = ExLibnice.set_remote_credentials(ice, credentials, stream_id)
    {result, state}
  end

  def handle_ice_message(
        :peer_candidate_gathering_done,
        _ctx,
        %State{ice: ice, stream_id: stream_id} = state
      ) do
    case ExLibnice.peer_candidate_gathering_done(ice, stream_id) do
      :ok -> {:ok, state}
      {:error, cause} -> {{:ok, notify: {:error, cause}}, state}
    end
  end

  def handle_ice_message(
        {:set_remote_candidate, candidate, component_id},
        _ctx,
        %State{ice: ice, stream_id: stream_id} = state
      ) do
    case ExLibnice.set_remote_candidate(ice, candidate, stream_id, component_id) do
      :ok -> {:ok, state}
      {:error, cause} -> {{:ok, notify: {:error, cause}}, state}
    end
  end

  def handle_ice_message({:new_candidate_full, _cand} = msg, _ctx, state) do
    Membrane.Logger.debug("#{inspect(msg)}")
    {{:ok, notify: msg}, state}
  end

  def handle_ice_message({:new_remote_candidate_full, _cand} = msg, _ctx, state) do
    Membrane.Logger.debug("#{inspect(msg)}")
    {{:ok, notify: msg}, state}
  end

  def handle_ice_message({:candidate_gathering_done, _stream_id} = msg, _ctx, state) do
    Membrane.Logger.debug("#{inspect(msg)}")
    {{:ok, notify: :candidate_gathering_done}, state}
  end

  def handle_ice_message(
        {:new_selected_pair, _stream_id, component_id, lfoundation, rfoundation} = msg,
        _ctx,
        state
      ) do
    Membrane.Logger.debug("#{inspect(msg)}")
    {{:ok, notify: {:new_selected_pair, component_id, lfoundation, rfoundation}}, state}
  end

  def handle_ice_message({:component_state_failed, _stream_id, component_id}, _ctx, state) do
    Membrane.Logger.warn("Component #{component_id} state FAILED")
    {:ok, state}
  end

  def handle_ice_message(msg, _ctx, state) do
    Membrane.Logger.warn("Unknown message #{inspect(msg)}")
    {:ok, state}
  end

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
  def parse_result(res, ice, stream_id, component_id, handshakes, handshake_status, state) do
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
