defmodule Image.Component.Integration.PictureTest do
  @moduledoc """
  End-to-end coverage of `<picture>` markup — both the
  format-fallback shape (`<.image formats={...}>`) and the
  art-direction shape (`<.picture sources={...}>`).
  """

  @fixtures Path.expand("../../../fixtures/images", __DIR__)

  use Image.Component.IntegrationCase,
    provider: {Image.Plug.Provider.Cloudflare, []},
    source_resolver: {Image.Plug.SourceResolver.File, root: @fixtures},
    on_error: :status_text

  defp common(ctx) do
    %{
      host: ctx.image_plug_host,
      scheme: "http"
    }
  end

  test "<.image formats={[:webp, :jpeg]}> — every <source type> URL returns the right MIME",
       ctx do
    html =
      render_component(
        &Image.Component.image/1,
        Map.merge(common(ctx), %{
          src: "/portrait.jpg",
          alt: "p",
          width: 400,
          height: 400,
          sizes: "100vw",
          formats: [:webp, :jpeg]
        })
      )

    doc = Floki.parse_fragment!(html)
    sources = Floki.find(doc, "picture > source")

    assert length(sources) == 2

    for source <- sources do
      [type] = Floki.attribute(source, "type")
      [srcset] = Floki.attribute(source, "srcset")

      for {url, {:width, _}} <- parse_srcset_string(srcset) do
        {:ok, response} = Req.get(url, decode_body: false)
        assert response.status == 200
        # The response Content-Type comes from the server's encoder,
        # not the source <source type>. They should match for raster
        # formats; for `:auto` they could differ. Both webp and
        # jpeg here are explicit so they must match.
        [response_ct] = response.headers["content-type"]
        assert response_ct =~ String.replace(type, "image/", "")
      end
    end
  end

  test "<.picture> art-direction — each <source media> serves images of its own width",
       ctx do
    sources = [
      %{
        media: "(min-width: 1024px)",
        src: "/portrait.jpg",
        width: 400,
        height: 400,
        sizes: "400px",
        formats: [:jpeg]
      },
      %{
        media: "(min-width: 480px)",
        src: "/portrait.jpg",
        width: 200,
        height: 200,
        sizes: "200px",
        formats: [:jpeg]
      }
    ]

    fallback = %{
      src: "/portrait.jpg",
      width: 100,
      height: 100,
      sizes: "100vw"
    }

    html =
      render_component(
        &Image.Component.Picture.picture/1,
        Map.merge(common(ctx), %{alt: "p", sources: sources, fallback: fallback})
      )

    doc = Floki.parse_fragment!(html)
    source_els = Floki.find(doc, "picture > source")

    # 2 breakpoints x 1 format each = 2 sources.
    assert length(source_els) == 2

    medias = source_els |> Enum.map(&(Floki.attribute(&1, "media") |> hd()))
    assert "(min-width: 1024px)" in medias
    assert "(min-width: 480px)" in medias

    # First source has intrinsic 400; entries should top out at 400.
    [first_source, second_source] = source_els

    [first_srcset] = Floki.attribute(first_source, "srcset")
    first_widths = parse_srcset_string(first_srcset) |> Enum.map(fn {_, {:width, w}} -> w end)
    assert Enum.max(first_widths) == 400

    [second_srcset] = Floki.attribute(second_source, "srcset")
    second_widths = parse_srcset_string(second_srcset) |> Enum.map(fn {_, {:width, w}} -> w end)
    assert Enum.max(second_widths) == 200

    # Fetch one URL from each source and validate the bytes.
    for source <- source_els do
      [srcset] = Floki.attribute(source, "srcset")

      for {url, {:width, expected_width}} <- parse_srcset_string(srcset) do
        {:ok, response} = Req.get(url, decode_body: false)
        assert response.status == 200
        {:ok, decoded} = Image.from_binary(response.body)
        assert Image.width(decoded) == expected_width
      end
    end

    # Fetch the fallback img.src too.
    [src] = image_srcs(html)
    {:ok, response} = Req.get(src, decode_body: false)
    assert response.status == 200
  end
end
