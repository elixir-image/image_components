defmodule Image.Components.IIIFComponentTest do
  @moduledoc """
  Tests for `Image.Components.IIIF.iiif/1` — the IIIF-specific
  component with `:static`, `:tiles`, and `:viewer` modes.
  """

  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias Image.Components.IIIF

  describe ":static mode (default)" do
    test "renders an <img> with the projected URL" do
      html =
        render_component(&IIIF.iiif/1,
          src: "/cat.jpg",
          host: "https://iiif.example.org",
          width: 400
        )

      assert html =~ ~s(<img )
      assert html =~ "https://iiif.example.org/iiif/3/cat.jpg/full/^400,/0/default.jpg"
    end

    test "honors iiif_quality={:gray}" do
      html =
        render_component(&IIIF.iiif/1, src: "/cat.jpg", iiif_quality: :gray, width: 200)

      assert html =~ "/0/gray.jpg"
    end

    test "honors region={{:pixels, x, y, w, h}}" do
      html =
        render_component(&IIIF.iiif/1,
          src: "/cat.jpg",
          region: {:pixels, 100, 50, 400, 300}
        )

      assert html =~ "/100,50,400,300/"
    end

    test "iiif_prefix overrides default" do
      html =
        render_component(&IIIF.iiif/1,
          src: "/cat.jpg",
          host: "https://iiif.wellcomecollection.org",
          iiif_prefix: "/image",
          width: 200
        )

      assert html =~ "https://iiif.wellcomecollection.org/image/cat.jpg/full/^200,/0/default.jpg"
    end

    test "passes through arbitrary HTML attributes" do
      html =
        render_component(&IIIF.iiif/1,
          src: "/cat.jpg",
          alt: "A cat",
          class: "thumb"
        )

      assert html =~ ~s(alt="A cat")
      assert html =~ ~s(class="thumb")
    end
  end

  describe ":tiles mode" do
    test "raises when source dimensions are missing" do
      assert_raise ArgumentError, ~r/requires `source_width` and `source_height`/, fn ->
        render_component(&IIIF.iiif/1,
          src: "/atlas.jpg",
          mode: :tiles,
          tile_width: 256
        )
      end
    end

    test "renders a 2×2 grid for a 1024×1024 source with 512 tiles at scale 1" do
      html =
        render_component(&IIIF.iiif/1,
          src: "/atlas.jpg",
          host: "https://iiif.example.org",
          mode: :tiles,
          source_width: 1024,
          source_height: 1024,
          tile_width: 512,
          scale_factor: 1
        )

      # Four tiles at (0,0), (512,0), (0,512), (512,512), each
      # 512×512 source pixels rendered at 512×512.
      assert html =~ "/0,0,512,512/512,512/0/default.jpg"
      assert html =~ "/512,0,512,512/512,512/0/default.jpg"
      assert html =~ "/0,512,512,512/512,512/0/default.jpg"
      assert html =~ "/512,512,512,512/512,512/0/default.jpg"

      # Outer container declares the source dims as the rendered grid size.
      assert html =~ ~s(width:1024px;height:1024px)
      # 4 <img> elements (one per tile).
      assert length(Regex.scan(~r/<img /, html)) == 4
    end

    test "renders a 3×2 grid for a 1500×1024 source with 512 tiles at scale 1" do
      html =
        render_component(&IIIF.iiif/1,
          src: "/atlas.jpg",
          mode: :tiles,
          source_width: 1500,
          source_height: 1024,
          tile_width: 512
        )

      # 6 tiles total: 3 columns × 2 rows.
      assert length(Regex.scan(~r/<img /, html)) == 6
      # Last column on each row is clipped to 1500-1024=476 pixels wide.
      assert html =~ "/1024,0,476,512/476,512/0/default.jpg"
      assert html =~ "/1024,512,476,512/476,512/0/default.jpg"
    end

    test "scale_factor 2 halves rendered dimensions and doubles region size" do
      html =
        render_component(&IIIF.iiif/1,
          src: "/atlas.jpg",
          mode: :tiles,
          source_width: 1024,
          source_height: 1024,
          tile_width: 256,
          scale_factor: 2
        )

      # tile_width=256, scale=2 → each tile covers 512 source pixels
      # rendered at 256. So 2×2 grid covering 1024×1024, rendered at 512×512.
      assert html =~ "/0,0,512,512/256,256/0/default.jpg"
      assert html =~ "/512,512,512,512/256,256/0/default.jpg"
      assert html =~ ~s(width:512px;height:512px)
      assert length(Regex.scan(~r/<img /, html)) == 4
    end

    test "format= changes the tile extension" do
      html =
        render_component(&IIIF.iiif/1,
          src: "/x.jpg",
          mode: :tiles,
          source_width: 512,
          source_height: 512,
          tile_width: 512,
          format: :webp
        )

      assert html =~ "/0/default.webp"
      refute html =~ ".jpg\""
    end

    test "iiif_quality={:gray} appears in every tile URL" do
      html =
        render_component(&IIIF.iiif/1,
          src: "/x.jpg",
          mode: :tiles,
          source_width: 512,
          source_height: 512,
          tile_width: 512,
          iiif_quality: :gray
        )

      assert html =~ "/0/gray.jpg"
      refute html =~ "/0/default."
    end

    test "honors host + iiif_prefix" do
      html =
        render_component(&IIIF.iiif/1,
          src: "/x.jpg",
          host: "https://iiif.wellcomecollection.org",
          iiif_prefix: "/image",
          mode: :tiles,
          source_width: 512,
          source_height: 512
        )

      assert html =~ "https://iiif.wellcomecollection.org/image/x.jpg/0,0,512,512/512,512/0/default.jpg"
    end
  end

  describe ":viewer mode" do
    test "renders a div with data-iiif-info-url and a fallback <img>" do
      html =
        render_component(&IIIF.iiif/1,
          src: "/portrait.jpg",
          host: "https://iiif.example.org",
          mode: :viewer
        )

      assert html =~ ~s(<div )
      assert html =~ ~s(data-iiif-info-url="https://iiif.example.org/iiif/3/portrait.jpg/info.json")
      assert html =~ ~s(data-iiif-viewer="openseadragon")
      assert html =~ ~s(<img )
    end

    test "viewer override comes through as data-iiif-viewer" do
      html = render_component(&IIIF.iiif/1, src: "/x.jpg", mode: :viewer, viewer: :mirador)
      assert html =~ ~s(data-iiif-viewer="mirador")
    end

    test "default container size 800×600" do
      html = render_component(&IIIF.iiif/1, src: "/x.jpg", mode: :viewer)
      assert html =~ "width:800px;height:600px"
    end

    test "explicit width / height honored" do
      html =
        render_component(&IIIF.iiif/1,
          src: "/x.jpg",
          mode: :viewer,
          width: 1200,
          height: 900
        )

      assert html =~ "width:1200px;height:900px"
    end

    test "fallback <img> uses fallback_size for the IIIF size segment" do
      html =
        render_component(&IIIF.iiif/1,
          src: "/x.jpg",
          mode: :viewer,
          fallback_size: 400
        )

      assert html =~ "/full/400,/0/default.jpg"
    end

    test "phx-hook + id pass through for LiveView hooking" do
      html =
        render_component(&IIIF.iiif/1,
          src: "/x.jpg",
          mode: :viewer,
          id: "v1",
          "phx-hook": "OpenSeadragon"
        )

      assert html =~ ~s(id="v1")
      assert html =~ ~s(phx-hook="OpenSeadragon")
    end
  end
end
