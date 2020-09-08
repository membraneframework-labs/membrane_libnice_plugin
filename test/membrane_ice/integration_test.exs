defmodule Membrane.ICE.IntegrationTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.Assertions

  alias Membrane.Testing

  @file_path "/tmp/ice-recv.h264"

  test "ice-trickle" do
    {:ok, tx_pid} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        module: Membrane.ICE.Support.TestSender
      })

    {:ok, rx_pid} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        module: Membrane.ICE.Support.TestReceiver
      })

    # setup sink
    Testing.Pipeline.message_child(tx_pid, :sink, {:add_stream, 1})
    assert_pipeline_notified(tx_pid, :sink, {:stream_id, tx_stream_id})
    Testing.Pipeline.message_child(tx_pid, :sink, {:get_local_credentials, tx_stream_id})
    assert_pipeline_notified(tx_pid, :sink, {:local_credentials, tx_credentials})

    # setup source
    Testing.Pipeline.message_child(rx_pid, :source, {:add_stream, 1})
    assert_pipeline_notified(rx_pid, :source, {:stream_id, rx_stream_id})
    Testing.Pipeline.message_child(rx_pid, :source, {:get_local_credentials, rx_stream_id})
    assert_pipeline_notified(rx_pid, :source, {:local_credentials, rx_credentials})

    # set credentials
    cred_msg = {:set_remote_credentials, rx_credentials, tx_stream_id}
    Testing.Pipeline.message_child(tx_pid, :sink, cred_msg)

    cred_msg = {:set_remote_credentials, tx_credentials, rx_stream_id}
    Testing.Pipeline.message_child(rx_pid, :source, cred_msg)

    # start connectivity checks
    Testing.Pipeline.message_child(tx_pid, :sink, {:gather_candidates, tx_stream_id})
    Testing.Pipeline.message_child(rx_pid, :source, {:gather_candidates, rx_stream_id})
    set_remote_candidates(tx_pid, rx_pid, tx_stream_id, rx_stream_id)

    # send and receive data
    Testing.Pipeline.play(rx_pid)
    Testing.Pipeline.play(tx_pid)

    :timer.sleep(2000)

    assert File.exists?(@file_path)

    %{size: size} = File.stat!(@file_path)
    assert size > 140_000
  end

  defp set_remote_candidates(
         tx_pid,
         rx_pid,
         tx_stream_id,
         rx_stream_id,
         tx_ready \\ false,
         rx_ready \\ false
       )

  defp set_remote_candidates(_tx_pid, _rx_pid, _tx_stream_id, _rx_stream_id, true, true) do
    :ok
  end

  defp set_remote_candidates(tx_pid, rx_pid, tx_stream_id, rx_stream_id, tx_ready, rx_ready) do
    # same both in tx_stream and rx_stream
    component_id = 1

    receive do
      {_tx_mod, ^tx_pid, {:handle_notification, {{:new_candidate_full, tx_cand}, :sink}}} ->
        msg = {:set_remote_candidate, tx_cand, rx_stream_id, component_id}
        Testing.Pipeline.message_child(rx_pid, :source, msg)
        set_remote_candidates(tx_pid, rx_pid, tx_stream_id, rx_stream_id, tx_ready, rx_ready)

      {_rx_mod, ^rx_pid,
       {:handle_notification, {{:component_state_ready, _stream_id, _component_id}, :source}}} ->
        set_remote_candidates(tx_pid, rx_pid, tx_stream_id, rx_stream_id, tx_ready, true)

      {_rx_mod, ^rx_pid, {:handle_notification, {{:new_candidate_full, rx_cand}, :source}}} ->
        msg = {:set_remote_candidate, rx_cand, tx_stream_id, component_id}
        Testing.Pipeline.message_child(tx_pid, :sink, msg)
        set_remote_candidates(tx_pid, rx_pid, tx_stream_id, rx_stream_id, tx_ready, rx_ready)

      {_tx_mod, ^tx_pid,
       {:handle_notification, {{:component_state_ready, _stream_id, _component_id}, :sink}}} ->
        set_remote_candidates(tx_pid, rx_pid, tx_stream_id, rx_stream_id, true, rx_ready)

      _other ->
        set_remote_candidates(tx_pid, rx_pid, tx_stream_id, rx_stream_id, tx_ready, rx_ready)
    after
      2000 -> assert false
    end
  end
end
