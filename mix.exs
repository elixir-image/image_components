defmodule Image.Components.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/elixir-image/image_components"

  def project do
    [
      app: :image_components,
      version: @version,
      elixir: "~> 1.15",
      description:
        "Phoenix.Component wrappers and per-CDN URL builders that project a canonical " <>
          "Image.Plug.Pipeline IR onto Cloudflare, Cloudinary, imgix, and ImageKit URL grammars.",
      package: package(),
      docs: docs(),
      deps: deps(),
      start_permanent: Mix.env() == :prod
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.1"},
      image_dep_with_path("image_plug", "~> 0.1"),
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},

      # Test-only — round-trip property tests + live-CDN HTTP checks.
      # See test/image/components/{property_test,live_cdn_test}.exs.
      {:stream_data, "~> 1.1", only: :test},
      {:req, "~> 0.5", only: :test},

      # `:image` is pulled transitively by `:image_plug`. We declare
      # it explicitly so the sibling-checkout override (when there's
      # an `../image/` directory) wins over the Hex resolution. The
      # test suite uses `Image.from_binary/1` to verify response
      # dimensions on live-CDN fetches; without that consumer-side
      # use, this dep wouldn't need to be declared at all.
      image_dep_with_path("image", "~> 0.67")
    ]
  end

  # In a sibling-checkout dev layout, prefer the on-disk path
  # override; otherwise fall back to the published Hex version.
  # Mirrors the helper in `image_playground/mix.exs`.
  defp image_dep_with_path(name, version, extra_options \\ []) do
    base =
      if File.exists?(Path.join(__DIR__, "../#{name}/mix.exs")) do
        [path: "../#{name}", override: true]
      else
        version
      end

    case base do
      list when is_list(list) -> {String.to_atom(name), Keyword.merge(list, extra_options)}
      version_string -> {String.to_atom(name), version_string, extra_options} |> normalise_dep()
    end
  end

  defp normalise_dep({name, version, []}), do: {name, version}
  defp normalise_dep({name, version, opts}), do: {name, version, opts}

  defp package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/v#{@version}/CHANGELOG.md"
      },
      files: ~w(lib guides mix.exs README.md CHANGELOG.md LICENSE.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "guides/usage.md",
        "guides/responsive.md",
        "guides/iiif.md",
        "guides/environments.md",
        "CHANGELOG.md",
        "LICENSE.md"
      ],
      groups_for_extras: [
        Guides: ~r{guides/},
        About: ~r/(README|CHANGELOG|LICENSE)\.md/
      ],
      groups_for_modules: [
        Components: [Image.Components],
        "URL builders": [Image.Components.URL]
      ]
    ]
  end
end
