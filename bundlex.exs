defmodule Membrane.ICE.BundlexProject do
  use Bundlex.Project

  def project do
    [
      nifs: nifs(Bundlex.platform())
    ]
  end

  defp nifs(_platform) do
    [
      agent: [
        sources: ["agent.c", "_generated/agent.c"],
        deps: [
          membrane_common_c: :membrane,
          unifex: :unifex
        ],
        pkg_configs: ["nice"]
      ]
    ]
  end
end
