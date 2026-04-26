defmodule Image.Component.Integration.GrammarDriftPropertyTest do
  @moduledoc """
  Property test that catches drift between `Image.Component.URL`'s
  Cloudflare URL grammar and `Image.Plug.Provider.Cloudflare.Options`'
  parser. For any random combination of width × layout × format,
  every URL the component emits must be one the plug accepts.

  If anyone changes one side without the other, this property
  fails on a reproducible seed.

  Reproduce a failure with:

      STREAM_DATA_SEED=12345 mix test test/image/component/integration/grammar_drift_property_test.exs
  """

  @fixtures Path.expand("../../../fixtures/images", __DIR__)

  use Image.Component.IntegrationCase,
    provider: {Image.Plug.Provider.Cloudflare, []},
    source_resolver: {Image.Plug.SourceResolver.File, root: @fixtures},
    on_error: :status_text

  use ExUnitProperties

  property "every component-generated srcset URL returns 200 with the right width", ctx do
    check all width <- integer(64..1024),
              layout <- member_of([:fixed, :constrained, :full_width]),
              format <- member_of([:jpeg, :png, :webp]),
              max_runs: 25 do
      assigns = %{
        src: "/portrait.jpg",
        alt: "x",
        sizes: "100vw",
        host: ctx.image_plug_host,
        scheme: "http",
        url_options: [format: format],
        layout: layout,
        width: width,
        height: width
      }

      html = render_component(&Image.Component.image/1, assigns)

      entries = parse_srcset(html)
      assert length(entries) > 0

      for {url, descriptor} <- entries do
        {:ok, response} = Req.get(url, decode_body: false)

        assert response.status == 200,
               "expected 200 for #{url} (descriptor #{inspect(descriptor)}), " <>
                 "got #{response.status}"

        {:ok, decoded} = Image.from_binary(response.body)
        actual_width = Image.width(decoded)

        case descriptor do
          {:width, expected} ->
            assert actual_width == expected,
                   "expected width #{expected}, got #{actual_width} for #{url}"

          {:density, factor} ->
            # For :fixed layout, density factor i ⇒ pixel width =
            # base_width × i.
            assert actual_width == width * factor,
                   "expected width #{width * factor}, got #{actual_width} for #{url}"
        end
      end
    end
  end
end
