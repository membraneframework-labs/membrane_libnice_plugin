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

As soon as connection is established sender side will download and send an example video file which
then will be received and saved under `/tmp/ice-recv.h264` by the other peer.

**Note**: after establishing ice connection on all input and output ICE Bin pads we send `HandshakeEvent`.
This event carries data returned by handshake module at the end of handshake and can be handled like
any other event in Membrane using `handle_event` callback in your elements linked to ICE Bin.
In this example we use the `Default` handshake module which means no handshake is performed after
establishing ICE connection.

Example implementation of `handle_event` callback can look like this:

```elixir
@impl true
def handle_event(_pad, %{handshake_data: handshake_data}, _ctx, state) do
  IO.inspect(handshake_data)
  {:ok, state}
end
```

You can use for e.g. [Membrane DTLS plugin](https://github.com/membraneframework/membrane_dtls_plugin.git)
to perform DTLS or DTLS-SRTP handshake after establishing ICE connection and then you will get some
binary data that will represent `keying material`. You can also implement your own
handshake modules by implementing `Membrane.ICE.Handshake` behaviour, but we will not cover this
in the example.

You can test received video with:
```bash
ffplay -f h264 /tmp/ice-recv.h264
```

That's it!
You have connected two hosts using ICE protocol and send an example video file.
