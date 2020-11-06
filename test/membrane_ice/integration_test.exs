defmodule Membrane.ICE.IntegrationTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.Assertions

  alias Membrane.Testing
  alias Membrane.ICE.Handshake

  @file_path "/tmp/ice-recv.h264"

  setup do
    File.rm(@file_path)
    assert !File.exists?(@file_path)
    :ok
  end

  test "trickle with default handshake" do
    {:ok, tx_pid} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        module: Membrane.ICE.Support.TestSender,
        custom_args: [handshake_module: Handshake.Default, handshake_opts: []]
      })

    {:ok, rx_pid} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        module: Membrane.ICE.Support.TestReceiver,
        custom_args: [
          handshake_module: Handshake.Default,
          handshake_opts: [],
          file_path: @file_path
        ]
      })

    Testing.Pipeline.prepare(tx_pid)
    Testing.Pipeline.prepare(rx_pid)
    Testing.Pipeline.play(rx_pid)

    # setup sink
    Testing.Pipeline.message_child(tx_pid, :sink, :get_local_credentials)
    assert_pipeline_notified(tx_pid, :sink, {:local_credentials, tx_credentials})

    # setup source
    Testing.Pipeline.message_child(rx_pid, :source, :get_local_credentials)
    assert_pipeline_notified(rx_pid, :source, {:local_credentials, rx_credentials})

    # set credentials
    cred_msg = {:set_remote_credentials, rx_credentials}
    Testing.Pipeline.message_child(tx_pid, :sink, cred_msg)

    cred_msg = {:set_remote_credentials, tx_credentials}
    Testing.Pipeline.message_child(rx_pid, :source, cred_msg)

    # start connectivity checks
    Testing.Pipeline.message_child(tx_pid, :sink, :gather_candidates)
    Testing.Pipeline.message_child(rx_pid, :source, :gather_candidates)
    set_remote_candidates(tx_pid, rx_pid)

    # send data
    Testing.Pipeline.play(tx_pid)

    :timer.sleep(1000)

    assert File.exists?(@file_path)

    %{size: size} = File.stat!(@file_path)
    assert size > 140_000
  end

  defp set_remote_candidates(
         tx_pid,
         rx_pid,
         tx_ready \\ false,
         rx_ready \\ false
       )

  defp set_remote_candidates(_tx_pid, _rx_pid, true, true) do
    :ok
  end

  defp set_remote_candidates(tx_pid, rx_pid, tx_ready, rx_ready) do
    # same both in tx_stream and rx_stream
    component_id = 1

    receive do
      {_tx_mod, ^tx_pid, {:handle_notification, {{:new_candidate_full, tx_cand}, :sink}}} ->
        msg = {:set_remote_candidate, tx_cand, component_id}
        Testing.Pipeline.message_child(rx_pid, :source, msg)
        set_remote_candidates(tx_pid, rx_pid, tx_ready, rx_ready)

      {_rx_mod, ^rx_pid,
       {:handle_notification, {{:component_state_ready, _component_id, _handshake_data}, :source}}} ->
        set_remote_candidates(tx_pid, rx_pid, tx_ready, true)

      {_rx_mod, ^rx_pid, {:handle_notification, {{:new_candidate_full, rx_cand}, :source}}} ->
        msg = {:set_remote_candidate, rx_cand, component_id}
        Testing.Pipeline.message_child(tx_pid, :sink, msg)
        set_remote_candidates(tx_pid, rx_pid, tx_ready, rx_ready)

      {_tx_mod, ^tx_pid,
       {:handle_notification, {{:component_state_ready, _component_id, _handshake_data}, :sink}}} ->
        set_remote_candidates(tx_pid, rx_pid, true, rx_ready)

      _other ->
        set_remote_candidates(tx_pid, rx_pid, tx_ready, rx_ready)
    after
      2000 -> assert false
    end
  end
end
