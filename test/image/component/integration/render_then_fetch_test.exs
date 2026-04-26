defmodule Image.Component.Integration.RenderThenFetchTest do
  @moduledoc """
  Render an `Image.Component` markup chunk against a running
  `Image.Plug`, then fetch every URL it emits and decode the
  bytes. Validates that the URLs the component generates are URLs
  the plug actually accepts and that the bytes match the
  descriptor's promised width.
  """

  @fixtures Path.expand("../../../fixtures/images", __DIR__)

  use Image.Component.IntegrationCase,
    provider: {Image.Plug.Provider.Cloudflare, []},
    source_resolver: {Image.Plug.SourceResolver.File, root: @fixtures},
    on_error: :status_text

  defp r(assigns), do: render_component(&Image.Component.image/1, assigns)

  test "every <img srcset> URL fetches a 200 image of the descriptor's width", ctx do
    html =
      r(%{
        src: "/portrait.jpg",
        alt: "p",
        width: 800,
        height: 600,
        sizes: "100vw",
        host: ctx.image_plug_host,
        scheme: "http",
        url_options: [format: :jpeg]
      })

    entries = parse_srcset(html)
    assert length(entries) > 0

    for {url, {:width, expected_width}} <- entries do
      {:ok, response} = Req.get(url, decode_body: false)

      assert response.status == 200,
             "expected 200 for #{url}, got #{response.status}"

      {:ok, decoded} = Image.from_binary(response.body)
      assert Image.width(decoded) == expected_width
    end
  end

  test "the bare <img src> attribute also returns 200 with the largest ladder width", ctx do
    html =
      r(%{
        src: "/portrait.jpg",
        alt: "p",
        width: 800,
        height: 600,
        sizes: "100vw",
        host: ctx.image_plug_host,
        scheme: "http",
        url_options: [format: :jpeg]
      })

    [src] = image_srcs(html)
    {:ok, response} = Req.get(src, decode_body: false)

    assert response.status == 200
    {:ok, decoded} = Image.from_binary(response.body)
    # The component sets the bare src to the largest ladder entry,
    # which for a constrained 800-wide layout is 800 (the intrinsic
    # width is included in the ladder).
    assert Image.width(decoded) == 800
  end
end
