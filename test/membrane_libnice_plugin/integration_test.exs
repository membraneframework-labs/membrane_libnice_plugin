defmodule Membrane.Libnice.IntegrationTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.Assertions

  alias Membrane.Testing
  alias Membrane.Libnice.Handshake

  @file_path "/tmp/ice-recv.h264"

  setup do
    File.rm(@file_path)
    assert !File.exists?(@file_path)
    :ok
  end

  test "trickle with default handshake" do
    {:ok, tx_pid} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        module: Membrane.Libnice.Support.TestSender,
        custom_args: [handshake_module: Handshake.Default, handshake_opts: []]
      })

    {:ok, rx_pid} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        module: Membrane.Libnice.Support.TestReceiver,
        custom_args: [
          handshake_module: Handshake.Default,
          handshake_opts: [],
          file_path: @file_path
        ]
      })

    :ok = Testing.Pipeline.play(rx_pid)
    :ok = Testing.Pipeline.play(tx_pid)

    # set credentials
    assert_pipeline_notified(rx_pid, :ice, {:local_credentials, rx_credentials})
    cred_msg = {:set_remote_credentials, rx_credentials}
    Testing.Pipeline.message_child(tx_pid, :ice, cred_msg)

    assert_pipeline_notified(tx_pid, :ice, {:local_credentials, tx_credentials})
    cred_msg = {:set_remote_credentials, tx_credentials}
    Testing.Pipeline.message_child(rx_pid, :ice, cred_msg)

    # start connectivity checks
    set_remote_candidates(tx_pid, rx_pid)

    :timer.sleep(1000)

    assert File.exists?(@file_path)

    %{size: size} = File.stat!(@file_path)
    assert size > 60_000

    Testing.Pipeline.stop_and_terminate(rx_pid, blocking?: true)
    Testing.Pipeline.stop_and_terminate(tx_pid, blocking?: true)
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
      {_tx_mod, ^tx_pid, {:handle_notification, {{:new_candidate_full, tx_cand}, :ice}}} ->
        msg = {:set_remote_candidate, tx_cand, component_id}
        Testing.Pipeline.message_child(rx_pid, :ice, msg)
        set_remote_candidates(tx_pid, rx_pid, tx_ready, rx_ready)

      {_rx_mod, ^rx_pid, {:handle_notification, {:candidate_gathering_done, :ice}}} ->
        set_remote_candidates(tx_pid, rx_pid, tx_ready, true)

      {_rx_mod, ^rx_pid, {:handle_notification, {{:new_candidate_full, rx_cand}, :ice}}} ->
        msg = {:set_remote_candidate, rx_cand, component_id}
        Testing.Pipeline.message_child(tx_pid, :ice, msg)
        set_remote_candidates(tx_pid, rx_pid, tx_ready, rx_ready)

      {_tx_mod, ^tx_pid, {:handle_notification, {:candidate_gathering_done, :ice}}} ->
        set_remote_candidates(tx_pid, rx_pid, true, rx_ready)

      _other ->
        set_remote_candidates(tx_pid, rx_pid, tx_ready, rx_ready)
    after
      2000 -> assert false
    end
  end
end
