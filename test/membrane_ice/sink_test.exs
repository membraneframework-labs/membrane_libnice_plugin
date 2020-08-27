defmodule Membrane.ICE.Sink.SinkTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.{Assertions, Pipeline}
  alias Membrane.Testing

  setup do
    {:ok, pid} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        elements: [
          sink: %Membrane.ICE.Sink{
            stun_servers: ['64.233.161.127:19302'],
            controlling_mode: 1
          }
        ]
      })

    [pid: pid]
  end

  test "adding streams", context do
    pid = context[:pid]
    Testing.Pipeline.message_child(pid, :sink, {:add_stream, 1})
    assert_pipeline_notified(pid, :sink, {:stream_id, stream_id})
    assert stream_id > 0
  end

  test "gathering candidates", context do
    pid = context[:pid]
    Testing.Pipeline.message_child(pid, :sink, {:add_stream, 1})
    Testing.Pipeline.message_child(pid, :sink, {:gather_candidates, 1})
    assert_pipeline_notified(pid, :sink, {:stream_id, stream_id})
    assert_pipeline_notified(pid, :sink, {:new_candidate_full, _candidate})
    assert_pipeline_notified(pid, :sink, {:candidate_gathering_done, ^stream_id})
  end

  test "getting local credentials", context do
    pid = context[:pid]
    Testing.Pipeline.message_child(pid, :sink, {:add_stream, 1})
    Testing.Pipeline.message_child(pid, :sink, {:gather_candidates, 1})
    Testing.Pipeline.message_child(pid, :sink, {:get_local_credentials, 1})
    assert_pipeline_notified(pid, :sink, {:local_credentials, _credentials})
  end

  test "setting local credentials", context do
#    pid = context[:pid]
#    Testing.Pipeline.message_child(pid, :sink, {:add_stream, 1})
#    Testing.Pipeline.message_child(pid, :sink, {:set_remote_credentials, 'asda', 1})
#    assert_pipeline_notified(pid, :sink, {:local_credentials, _credentials})
  end

  test "setting remote candidate", context do
#    pid = context[:pid]
#    Testing.Pipeline.message_child(pid, :sink, {:add_stream, 1})
  end
end
