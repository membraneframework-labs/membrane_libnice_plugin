defmodule Membrane.ICE.Sink.SinkTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.Assertions
  alias Membrane.Testing

  setup do
    {:ok, tx_pid} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        elements: [
          sink: %Membrane.ICE.Sink{
            stun_servers: ['64.233.161.127:19302'],
            controlling_mode: true
          }
        ]
      })

    {:ok, rx_pid} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        elements: [
          source: %Membrane.ICE.Source{
            stun_servers: ['64.233.161.127:19302'],
            controlling_mode: false
          }
        ]
      })

    [tx_pid: tx_pid, rx_pid: rx_pid]
  end

  describe "add stream" do
    test "sink", context do
      test_adding_stream(:sink, context[:tx_pid])
    end

    test "source", context do
      test_adding_stream(:source, context[:rx_pid])
    end

    defp test_adding_stream(element, pid) do
      Testing.Pipeline.message_child(pid, element, {:add_stream, 1})
      assert_pipeline_notified(pid, element, {:stream_id, stream_id})
      assert stream_id > 0

      Testing.Pipeline.message_child(pid, element, {:add_stream, 1, ''})
      assert_pipeline_notified(pid, element, {:stream_id, stream_id})
      assert stream_id > 0

      Testing.Pipeline.message_child(pid, element, {:add_stream, 1, 'audio'})
      assert_pipeline_notified(pid, element, {:stream_id, stream_id})
      assert stream_id > 0

      Testing.Pipeline.message_child(pid, element, {:add_stream, 1, 'audio'})
      assert_pipeline_notified(pid, element, {:error, :invalid_stream_or_duplicate_name})
    end
  end

  describe "generate_local_sdp" do
    test "sink", context do
      test_generating_local_sdp(:sink, context[:tx_pid])
    end

    test "source", context do
      test_generating_local_sdp(:source, context[:rx_pid])
    end

    defp test_generating_local_sdp(element, pid) do
      Testing.Pipeline.message_child(pid, element, {:add_stream, 1, 'audio'})
      assert_pipeline_notified(pid, element, {:stream_id, stream_id})
      Testing.Pipeline.message_child(pid, element, :generate_local_sdp)
      assert_pipeline_notified(pid, element, {:local_sdp, sdp})
      assert String.contains?(List.to_string(sdp), ["v=0", "m=audio", "a=ice-ufrag", "a=ice-pwd"])
    end
  end

  describe "parse_remote_sdp" do
    test "sink", context do
      test_parsing_remote_sdp(:sink, context[:tx_pid])
    end

    test "source", context do
      test_generating_local_sdp(:source, context[:rx_pid])
    end

    defp test_parsing_remote_sdp(element, pid) do
      Testing.Pipeline.message_child(pid, element, {:add_stream, 1, 'audio'})
      assert_pipeline_notified(pid, element, {:stream_id, stream_id})

      Testing.Pipeline.message_child(
        pid,
        element,
        {:parse_remote_sdp,
         'v=0\r\nm=audio 0 ICE/SDP\nc=IN IP4 0.0.0.0\na=ice-ufrag:8Fp+\na=ice-pwd:BVsIrRqHCcr/lr7JPgHa8k\n'}
      )

      assert_pipeline_notified(pid, element, {:parse_remote_sdp_ok, 0})

      Process.flag(:trap_exit, true)

      Testing.Pipeline.message_child(
        pid,
        element,
        {:parse_remote_sdp,
         'v=0\r\nm=audio 0 ICE/SDP\nc=IN IP4 0.0.0.0\na=ice-ufrag:8Fp+\na=ice-pwd:BVsIrRqHCcr/lr7JPgHa8k\nm=audio 0 ICE/SDP\nc=IN IP4 0.0.0.0\na=ice-ufrag:8Fp+\na=ice-pwd:BVsIrRqHCcr/lr7JPgHa8k\n'}
      )

      assert_receive({:EXIT, ^pid, {:error, {:cannot_handle_message, :failed_to_parse_sdp, _}}})
    end
  end

  describe "get local credentials" do
    test "sink", context do
      test_getting_local_credentials(:sink, context[:tx_pid])
    end

    test "source", context do
      test_getting_local_credentials(:source, context[:rx_pid])
    end

    defp test_getting_local_credentials(element, pid) do
      Testing.Pipeline.message_child(pid, element, {:add_stream, 1})
      assert_pipeline_notified(pid, element, {:stream_id, stream_id})
      Testing.Pipeline.message_child(pid, element, {:gather_candidates, stream_id})
      Testing.Pipeline.message_child(pid, element, {:get_local_credentials, stream_id})
      assert_pipeline_notified(pid, element, {:local_credentials, _credentials})
    end
  end

  describe "set remote credentials" do
    test "sink", context do
      test_setting_remote_credentials(:sink, context[:tx_pid])
    end

    test "source", context do
      test_setting_remote_credentials(:source, context[:rx_pid])
    end

    defp test_setting_remote_credentials(element, pid) do
      Testing.Pipeline.message_child(pid, element, {:add_stream, 1})
      assert_pipeline_notified(pid, element, {:stream_id, stream_id})

      Testing.Pipeline.message_child(
        pid,
        element,
        {:set_remote_credentials, 'DWIS nuNjkHVrkUZsfLJisHGWHy', 1}
      )

      refute_receive(
        {:EXIT, ^pid, {:error, {:cannot_handle_message, :failed_to_set_credentials, _}}}
      )

      Process.flag(:trap_exit, true)

      Testing.Pipeline.message_child(
        pid,
        element,
        {:set_remote_credentials, 'invalid_cred', stream_id}
      )

      assert_receive(
        {:EXIT, ^pid, {:error, {:cannot_handle_message, :failed_to_set_credentials, _}}}
      )
    end
  end

  describe "gather candidates" do
    test "sink", context do
      test_gathering_candidates(:sink, context[:tx_pid])
    end

    test "source", context do
      test_gathering_candidates(:source, context[:rx_pid])
    end

    defp test_gathering_candidates(element, pid) do
      Testing.Pipeline.message_child(pid, element, {:add_stream, 1})
      assert_pipeline_notified(pid, element, {:stream_id, stream_id})
      Testing.Pipeline.message_child(pid, element, {:gather_candidates, stream_id})
      assert_pipeline_notified(pid, element, {:new_candidate_full, _candidate})
      assert_pipeline_notified(pid, element, {:candidate_gathering_done, ^stream_id})

      Process.flag(:trap_exit, true)
      Testing.Pipeline.message_child(pid, element, {:gather_candidates, 2000})

      assert_receive(
        {:EXIT, ^pid, {:error, {:cannot_handle_message, :invalid_stream_or_allocation, _}}}
      )
    end
  end

  describe "peer candidate gathering done" do
    test "sink", context do
      test_peer_candidate_gathering_done(:sink, context[:tx_pid])
    end

    test "source", context do
      test_peer_candidate_gathering_done(:source, context[:rx_pid])
    end

    defp test_peer_candidate_gathering_done(element, pid) do
      Testing.Pipeline.message_child(pid, element, {:add_stream, 1})
      assert_pipeline_notified(pid, element, {:stream_id, stream_id})
      Testing.Pipeline.message_child(pid, element, {:peer_candidate_gathering_done, stream_id})
      refute_pipeline_notified(pid, element, {:error, :stream_not_found})
      Testing.Pipeline.message_child(pid, element, {:peer_candidate_gathering_done, 2000})
      assert_pipeline_notified(pid, element, {:error, :stream_not_found})
    end
  end

  describe "set remote candidate" do
    test "sink", context do
      test_setting_remote_candidate(:sink, context[:tx_pid])
    end

    test "source", context do
      test_setting_remote_candidate(:source, context[:rx_pid])
    end

    defp test_setting_remote_candidate(element, pid) do
      Testing.Pipeline.message_child(pid, element, {:add_stream, 1})
      assert_pipeline_notified(pid, element, {:stream_id, stream_id})

      Testing.Pipeline.message_child(
        pid,
        element,
        {:set_remote_candidate, 'a=candidate:1 1 UDP 2015363327 192.168.83.205 38292 typ host',
         stream_id, 1}
      )

      refute_pipeline_notified(pid, element, {:error, :failed_to_parse_sdp_string})

      Testing.Pipeline.message_child(
        pid,
        element,
        {:set_remote_candidate, 'invalid_sdp_string', stream_id, 1}
      )

      assert_pipeline_notified(pid, element, {:error, :failed_to_parse_sdp_string})
    end
  end
end
