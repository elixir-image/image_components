defmodule Image.Component.Integration.LayoutsTest do
  @moduledoc """
  End-to-end coverage of each layout mode (`:fixed | :constrained
  | :full_width`). For each mode, render a component, parse the
  emitted srcset, fetch every URL, and assert the bytes match the
  descriptor's promised dimension.
  """

  @fixtures Path.expand("../../../fixtures/images", __DIR__)

  use Image.Component.IntegrationCase,
    provider: {Image.Plug.Provider.Cloudflare, []},
    source_resolver: {Image.Plug.SourceResolver.File, root: @fixtures},
    on_error: :status_text

  defp r(assigns), do: render_component(&Image.Component.image/1, assigns)

  defp common(ctx) do
    %{
      src: "/portrait.jpg",
      alt: "p",
      host: ctx.image_plug_host,
      scheme: "http",
      url_options: [format: :jpeg]
    }
  end

  test ":constrained — every Nw URL returns an image of width N", ctx do
    html = r(Map.merge(common(ctx), %{width: 800, height: 600, sizes: "100vw", layout: :constrained}))

    entries = parse_srcset(html)
    assert length(entries) > 0

    for {url, {:width, expected_width}} <- entries do
      {:ok, response} = Req.get(url, decode_body: false)
      assert response.status == 200
      {:ok, decoded} = Image.from_binary(response.body)
      assert Image.width(decoded) == expected_width
    end
  end

  test ":fixed — Nx URLs return images of width = base_width × N", ctx do
    base_width = 100

    html =
      r(Map.merge(common(ctx), %{width: base_width, height: base_width, layout: :fixed}))

    entries = parse_srcset(html)
    assert length(entries) > 0

    for {url, {:density, factor}} <- entries do
      {:ok, response} = Req.get(url, decode_body: false)
      assert response.status == 200
      {:ok, decoded} = Image.from_binary(response.body)
      assert Image.width(decoded) == base_width * factor
    end
  end

  test ":full_width — every Nw URL returns an image of width N", ctx do
    html = r(Map.merge(common(ctx), %{layout: :full_width, sizes: "100vw"}))

    entries = parse_srcset(html)
    assert length(entries) > 0

    for {url, {:width, expected_width}} <- entries do
      {:ok, response} = Req.get(url, decode_body: false)
      assert response.status == 200
      {:ok, decoded} = Image.from_binary(response.body)
      assert Image.width(decoded) == expected_width
    end
  end
end
