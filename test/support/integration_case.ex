defmodule Image.Component.IntegrationCase do
  @moduledoc """
  Test case template for end-to-end render-then-fetch tests of
  `Image.Component`.

  Starts an `Image.Plug` Bandit server on a random port in
  `setup_all`, mounted with the supplied configuration. Tests can
  render `Image.Component` markup pointing at the running plug
  (via the `host:` attr) and then fetch each emitted URL to verify
  the round-trip.

  ### Usage

      defmodule MyComponentIntegrationTest do
        @fixtures Path.expand("../../fixtures/images", __DIR__)

        use Image.Component.IntegrationCase,
          provider: {Image.Plug.Provider.Cloudflare, []},
          source_resolver: {Image.Plug.SourceResolver.File, root: @fixtures},
          on_error: :status_text
      end

      test "constrained <.image> srcset URLs all return 200", ctx do
        html =
          render_component(&Image.Component.image/1, %{
            src: "/portrait.jpg",
            alt: "p",
            width: 800,
            height: 600,
            sizes: "100vw",
            host: ctx.image_plug_host,
            scheme: "http"
          })

        for {url, expected_w} <- parse_srcset(html) do
          {:ok, response} = Req.get(url, decode_body: false)
          assert response.status == 200
          {:ok, decoded} = Image.from_binary(response.body)
          assert Image.width(decoded) == expected_w
        end
      end

  """

  @doc false
  defmacro __using__(plug_options) do
    quote do
      use ExUnit.Case, async: false
      import Phoenix.LiveViewTest
      import Image.Component.IntegrationCase

      @plug_options unquote(plug_options)

      setup_all do
        Image.Component.IntegrationCase.start(@plug_options)
      end
    end
  end

  @doc """
  Starts a Bandit server on a random port mounted with the supplied
  `Image.Plug` configuration.

  ### Returns

  * `{:ok, %{image_plug_host: "127.0.0.1:<port>", base_url: "http://...", port: ...}}`
    — for use as a `setup_all` context.

  """
  @spec start(keyword()) :: {:ok, map()}
  def start(plug_options) do
    {:ok, server_pid} =
      Bandit.start_link(
        plug: {Image.Plug, plug_options},
        port: 0,
        startup_log: false
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server_pid)

    ExUnit.Callbacks.on_exit(fn ->
      if Process.alive?(server_pid), do: Process.exit(server_pid, :shutdown)
    end)

    {:ok,
     %{
       image_plug_host: "127.0.0.1:#{port}",
       base_url: "http://127.0.0.1:#{port}",
       port: port,
       server: server_pid
     }}
  end

  @doc """
  Parses a rendered HTML string and returns the URL of every `<img>`
  in document order.

  Useful for asserting "the first image is rendered with this src".
  """
  @spec image_srcs(String.t()) :: [String.t()]
  def image_srcs(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find("img")
    |> Enum.flat_map(&Floki.attribute(&1, "src"))
  end

  @doc """
  Parses a rendered HTML string and returns the parsed `srcset`
  entries from every `<img>` and `<source>` element.

  Returns a list of `{url, descriptor}` tuples where `descriptor`
  is either `{:width, integer}` (for `Nw` entries) or
  `{:density, integer}` (for `Nx` entries).
  """
  @spec parse_srcset(String.t() | Floki.html_tree()) :: [{String.t(), {atom(), integer()}}]
  def parse_srcset(html) when is_binary(html) do
    html
    |> Floki.parse_fragment!()
    |> parse_srcset()
  end

  def parse_srcset(doc) when is_list(doc) do
    doc
    |> Floki.find("img, source")
    |> Enum.flat_map(&Floki.attribute(&1, "srcset"))
    |> Enum.flat_map(&parse_srcset_attr/1)
  end

  @doc """
  Parses a bare `srcset` attribute string (without surrounding HTML).
  Use when you've already extracted the attribute via Floki.
  """
  @spec parse_srcset_string(String.t()) :: [{String.t(), {atom(), integer()}}]
  def parse_srcset_string(srcset) when is_binary(srcset), do: parse_srcset_attr(srcset)

  defp parse_srcset_attr(srcset) when is_binary(srcset) do
    # The srcset grammar separates entries with `,` followed by
    # whitespace, but URLs may contain `,` themselves (e.g. the
    # Cloudflare `<options>` segment). Match each entry as
    # `<url> <number><w|x>` via regex instead.
    Regex.scan(~r/(\S+)\s+(\d+)([wx])(?:\s*,\s*|\s*$)/, srcset)
    |> Enum.map(fn
      [_, url, value, "w"] -> {url, {:width, String.to_integer(value)}}
      [_, url, value, "x"] -> {url, {:density, String.to_integer(value)}}
    end)
  end
end
