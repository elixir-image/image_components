defmodule Image.Component.MixProject do
  use Mix.Project

  @version "0.1.0-rc.0"
  @source_url "https://github.com/kipcole9/image_components"

  def project do
    [
      app: :image_components,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      package: package(),
      description: description(),
      source_url: @source_url,
      docs: docs(),
      dialyzer: [
        plt_add_apps: [:phoenix_live_view, :ex_unit],
        flags: [:error_handling, :unknown, :extra_return]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:phoenix_live_view, "~> 1.0"},
      {:floki, ">= 0.30.0", only: :test},
      # Test-only path-dep on the sibling image_plug for end-to-end
      # render-then-fetch integration tests. Not part of the
      # published package.
      {:image_plug, path: "../image_plug", only: :test},
      {:bandit, "~> 1.5", only: :test},
      {:req, "~> 0.5", only: :test},
      {:stream_data, "~> 1.1", only: :test},
      {:ex_doc, "~> 0.34", only: [:dev, :release], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Phoenix LiveView responsive-image component. Builds <img srcset>/" <>
      "<picture> markup against any image-CDN that speaks the Cloudflare " <>
      "Images URL grammar (including image_plug)."
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE.md",
        "logo.jpg",
        "guides"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "logo.jpg",
      extras: ["README.md", "guides/usage.md", "CHANGELOG.md"],
      groups_for_extras: [
        "Guides": ~r{guides/},
        "About": ["README.md", "CHANGELOG.md"]
      ],
      source_ref: "v#{@version}"
    ]
  end
end
