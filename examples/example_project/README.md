# Example

In this example we will establish connection between two peers using `membrane_ice_plugin` and
send an example video file.
Beside the sender and receiver code we will need something we call `AddressProvider`.
It is a simple module that extends each message with metadata indicating where this particular
message should be sent.

## Requirements

To run this example you will need a test video named `test-video.h264` stored in `~/Videos/`.
You can change this in `sender.ex` file.
Example video is available [here](https://membraneframework.github.io/static/video-samples/test-video.h264).

## Usage

On a sender machine type
```elixir
iex -S mix
iex(1)> {:ok, pid} = Example.Sender.start_link()
{:ok, #PID<0.274.0>}
iex(bundlex_app_e708a08e-f518-40c1-9518-9fe274a66445@localhost)2> Example.Sender.play(pid)
:ok
pipeline: {:stream_id, 1}
pipeline: {:new_candidate_full,
 'a=candidate:1 1 UDP 2015363327 <some_ip> <some_port> typ host'}
...
pipeline: :gathering_done
pipeline: {:local_credentials, 'Bozj SzGPRQ3eZ9gMzl03wvCYLV'}
```

This will result in getting local candidates as well as local credentials.
Do the same on a receiver machine. Type:
```elixir
iex -S mix
iex(1)> {:ok, pid} = Example.Receiver.start_link()
{:ok, #PID<0.1130.0>}
iex(bundlex_app_6d8e8880-a91f-47b6-8c09-707770555bec@membrane-test1)2> Example.Receiver.play(pid)
:ok
pipeline: {:stream_id, 1}
pipeline: {:new_candidate_full,
 'a=candidate:1 1 UDP 2015363327 <some_ip> <some_port> typ host'}
...
pipeline: :gathering_done
pipeline: {:local_credentials, 'THp3 pg47Jtr2AlNGd9l2u+aQfG'}
```

Now we have sender and receiver credentials and candidates.
Set them both on the sender and receiver machines in the following way:
```elixir
iex(...)> send(pid, {:set_remote_credentials, '<credentials>', 1}) # 1 is for stream_id
```
Remember to pass receiver credentials on sender machine and sender credentials on receiver machine.

At this moment we can start setting candidates
```elixir
iex(...)> send(pid, {:set_remote_candidate, 'a=candidate:1 1 UDP 2015363327 <some_ip> <some_port> typ host'})
```
This will start connection establishment attempts.

If connection establishes your receiver will automatically get example video file in `/tmp/ice-recv.h264`.
