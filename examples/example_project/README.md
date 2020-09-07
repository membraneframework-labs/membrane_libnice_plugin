# Example

This example shows how to establish connection between two peers using `membrane_ice_plugin` and
send an example video file.
We will use [Membrane Hackney Element](https://github.com/membraneframework/membrane-element-hackney)
for downloading an example video file and [Membrane File Element](https://github.com/membraneframework/membrane-element-file)
for saving it into a file.

Let's start!

## Usage

At first, we have to initialize our sender and receiver machines.
Let's start with a sender one, type:
```elixir
iex -S mix
iex(1)> {:ok, pid} = Example.Sender.start_link()
{:ok, #PID<0.274.0>}
iex(bundlex_app_...)2> send(pid, :init)
:init
```

Sending `:init` message will add a new stream with one component as well as generate local SDP
containing information about stream and credentials. It will also start gathering candidates
process.
Your output should look similarly to this:
```elixir
[info]  [pipeline@<0.366.0>] {stream_id: 1}

[debug] [:sink] local sdp: "v=0\r\nm=- 0 ICE/SDP\nc=IN IP4 0.0.0.0\na=ice-ufrag:Zdu1\na=ice-pwd:4nRN+sSf8Ednd+MFA1FK8Q\n"

[info]  [pipeline@<0.366.0>] {:new_candidate_full, "a=candidate:1 1 UDP 2015363327 192.168.83.205 38292 typ host"}

...
```

Now do the same on the receiver machine. Type:
```elixir
iex -S mix
iex(1)> {:ok, pid} = Example.Receiver.start_link()
{:ok, #PID<0.351.0>}
iex(bundlex_app_...)2> send(pid, :init)
:init
```
Again you should see logs with local SDP and candidates.

Next step is to exchange gathered information between peers.
In order to do this type on the receiver machine:

```elixir
iex(...)> send(pid, {:parse_remote_sdp, "v=0\r\nm=- 0 ICE/SDP\nc=IN IP4 0.0.0.0\na=ice-ufrag:Zdu1\na=ice-pwd:4nRN+sSf8Ednd+MFA1FK8Q\n"})
```

and the same on the sender side.
Remember to pass relevant SDPs.


Time to exchange our candidates and start connectivity checks.
We will do it by typing:

```elixir
iex(...)> send(pid, {:set_remote_candidate, "a=candidate:1 1 UDP 2015363327 <some_ip> <some_port> typ host"})
```
This will start connection establishment attempts.

After setting remote candidates both for the sender and receiver you should see logs similar to

```elixir
12:13:17.143 [info]  [pipeline@<0.551.0>] {:new_selected_pair, 1, 1, "4", "7"}

12:13:17.143 [info]  [pipeline@<0.551.0>] {:component_state_ready, 1, 1}
```

both on the sender and receiver side.

At this moment we know that our peers are in the READY state and should be able to send and receive
messages.
Let's check it.

At first type on the receiver:
```elixir
Example.Receiver.play(pid)
```

and then on the sender:
```elixir
Example.Sender.play(pid)
```

It is important to `play` receiver at first because it has to prepare its internal element
for receiving buffers and saving them into a proper file.
In other case received buffers would be ignored (until you call `Example.Receiver.play(pid)`).

After making both sides playing, the sender will download an example video file and send it to the
receiver which will then save it to `/tmp` directory under `ice-recv.h264` file.

You can test received video with:
```bash
ffplay -f h264 /tmp/ice-recv.h264
```

That's it!
You have connected two hosts using ICE protocol and send an example video file.
Congrats!
