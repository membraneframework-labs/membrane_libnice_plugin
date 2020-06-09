defmodule Membrane.ICE.BundlexProject do
  use Bundlex.Project

  def project do
    [
      nifs: nifs(Bundlex.platform())
    ]
  end

  defp nifs(_platform) do
    [
      native: [
        sources: ["native.c", "_generated/native.c"],
        deps: [membrane_common_c: :membrane, unifex: :unifex]
      ]
    ]
  end
end
