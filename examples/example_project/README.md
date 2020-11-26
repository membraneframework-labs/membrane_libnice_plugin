# Example

This example shows how to establish a connection between two peers using `membrane_ice_plugin` and
send an example video file.
We will use [Membrane Hackney plugin](https://github.com/membraneframework/membrane_hackney_plugin)
for downloading the example video file and [Membrane File plugin](https://github.com/membraneframework/membrane_file_plugin)
for saving it to a file.

Let's start!

## Usage

At first, we have to initialize our sender and receiver machines.
Let's start with a sender one, type:
```elixir
iex -S mix
iex(1)> {:ok, pid} = Example.Sender.start_link()
{:ok, #PID<0.328.0>}
iex(bundlex_app_...)2> Example.Sender.play(pid)
```

Invoking `Exmaple.Sender.play(pid)` will add a new stream with one component and
make our sink sending data as soon as we establish connection with our peer. We will also
start receiving messages e.g. local credentials and candidates.
Your output should look similarly to this:
```elixir
...
[info]  [pipeline@<0.328.0>] {:local_credentials, "LjQN t6CnLkos4AACsHXmCklKD3"}
...
[info]  [pipeline@<0.328.0>] {:new_candidate_full, "a=candidate:1 1 UDP 2015363327 192.168.83.205 38292 typ host"}
...
[info]  [pipeline@<0.328.0>] Pipeline playback state changed from prepared to playing
...
```

Now do the same on the receiver host. Type:
```elixir
iex -S mix
iex(1)> {:ok, pid} = Example.Receiver.start_link()
{:ok, #PID<0.351.0>}
iex(bundlex_app_...)2> Example.Sender.play(pid)
```
Again you should see logs with local credentials and candidates.

Next step is to exchange gathered information between peers.
In order to do this type on the receiver machine:

```elixir
iex(...)> send(pid, {:set_remote_credentials, "LjQN t6CnLkos4AACsHXmCklKD3"})
```

and the same on the sender side.
Remember to pass relevant credentials.


Time to exchange our candidates and start connectivity checks.
We will do it by typing:

```elixir
iex(...)> send(pid, {:set_remote_candidate, "a=candidate:1 1 UDP 2015363327 <some_ip> <some_port> typ host"})
```
This will start connection establishment attempts.

After setting remote candidates both for the sender and receiver you should see logs similar to

```elixir
12:13:17.143 [info]  [pipeline@<0.551.0>] {:new_selected_pair, 1, "4", "7"}

12:13:17.143 [info]  [pipeline@<0.551.0>] {:component_state_ready, 1, nil}
```

both on the sender and receiver side.

`nil` in `{:component_state_ready, 1, nil}` is returned as `handshake_data`. In this example we use
the `Default` handshake module which means no handshake is performed after establishing ICE
connection. You can use for e.g. [Membrane DTLS plugin](https://github.com/membraneframework/membrane_dtls_plugin.git)
to perform DTLS or DTLS-SRTP handshake after establishing ICE connection and then you will get some
binary data that will represent `keying material` instead of `nil`. You can also implement your own
handshake modules by implementing `Membrane.ICE.Handshake` behaviour, but we will not cover this
in the example.

At this moment we know that our peers are in the READY state. The sender will instantly send an
example video file to the receiver which will then save to `/tmp` directory under `ice-recv.h264`
file.

You can test received video with:
```bash
ffplay -f h264 /tmp/ice-recv.h264
```

That's it!
You have connected two hosts using ICE protocol and send an example video file.
