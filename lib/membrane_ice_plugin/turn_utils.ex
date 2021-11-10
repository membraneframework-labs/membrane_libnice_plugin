defmodule Membrane.ICE.TurnUtils do
  @moduledoc false

  @spec generate_secret() :: binary()
  def generate_secret() do
    symbols = '0123456789abcdef'

    1..20
    |> Enum.map(fn _i -> Enum.random(symbols) end)
    |> to_string()
  end

  @spec start_integrated_turn(binary(), list()) :: {:ok, :inet.port_number(), pid()}
  def start_integrated_turn(secret, opts \\ []),
    do: :turn_starter.start(secret, opts)

  @spec stop_integrated_turn(map()) :: :ok
  def stop_integrated_turn(turn),
    do: :turn_starter.stop(turn.server_addr, turn.server_port, turn.relay_type)
end
