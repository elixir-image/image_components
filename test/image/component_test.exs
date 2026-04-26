defmodule Image.ComponentTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  defp r(assigns) do
    render_component(&Image.Component.image/1, assigns)
  end

  defp parse(html), do: Floki.parse_fragment!(html)

  describe "default constrained layout" do
    test "renders a single <img> with width-descriptor srcset, sizes, alt, dims, decoding" do
      html =
        r(%{
          src: "/photos/sunset.jpg",
          alt: "Sunset",
          width: 800,
          height: 600,
          sizes: "100vw"
        })

      doc = parse(html)
      [img] = Floki.find(doc, "img")

      assert Floki.attribute(img, "src") |> hd() =~ "/cdn-cgi/image/width=800/photos/sunset.jpg"
      assert Floki.attribute(img, "alt") == ["Sunset"]
      assert Floki.attribute(img, "width") == ["800"]
      assert Floki.attribute(img, "height") == ["600"]
      assert Floki.attribute(img, "decoding") == ["async"]
      assert Floki.attribute(img, "sizes") == ["100vw"]

      [srcset] = Floki.attribute(img, "srcset")
      assert srcset =~ "320w"
      assert srcset =~ "800w"
      refute srcset =~ "1600w"
    end

    test "style sets aspect-ratio for CLS prevention" do
      html =
        r(%{
          src: "/x.jpg",
          alt: "x",
          width: 800,
          height: 600,
          sizes: "100vw"
        })

      [img] = parse(html) |> Floki.find("img")
      [style] = Floki.attribute(img, "style")

      assert style =~ "aspect-ratio: 800 / 600"
      assert style =~ "max-width: 800px"
    end
  end

  describe "fixed layout" do
    test "renders a density-descriptor srcset and no `sizes` attribute" do
      html =
        r(%{
          src: "/icon.png",
          alt: "Icon",
          width: 100,
          height: 100,
          layout: :fixed
        })

      [img] = parse(html) |> Floki.find("img")
      [srcset] = Floki.attribute(img, "srcset")

      assert srcset =~ "1x"
      assert srcset =~ "2x"
      assert srcset =~ "3x"
      refute srcset =~ "100w"

      # `sizes` is not meaningful for density-descriptor srcsets;
      # it must be absent (or empty) so the browser falls back
      # purely to DPR selection.
      sizes_attr = Floki.attribute(img, "sizes")
      assert sizes_attr == [] or sizes_attr == [""]
    end

    test "renders inline style with explicit pixel dimensions" do
      html =
        r(%{src: "/x.png", alt: "x", width: 100, height: 100, layout: :fixed})

      [img] = parse(html) |> Floki.find("img")
      [style] = Floki.attribute(img, "style")

      assert style =~ "width: 100px"
      assert style =~ "height: 100px"
    end
  end

  describe "full_width layout" do
    test "fills the viewport with width-descriptor srcset" do
      html =
        r(%{
          src: "/hero.jpg",
          alt: "Hero",
          layout: :full_width,
          sizes: "100vw"
        })

      [img] = parse(html) |> Floki.find("img")
      [style] = Floki.attribute(img, "style")
      [srcset] = Floki.attribute(img, "srcset")

      assert style == "width: 100%; height: auto;"
      assert srcset =~ "640w"
    end
  end

  describe "formats / <picture>" do
    test "with formats: [:avif, :webp] renders <picture> with one <source> per format" do
      html =
        r(%{
          src: "/p.jpg",
          alt: "p",
          width: 800,
          height: 600,
          formats: [:avif, :webp],
          sizes: "100vw"
        })

      doc = parse(html)
      sources = Floki.find(doc, "picture > source")

      assert length(sources) == 2
      types = Enum.map(sources, &(Floki.attribute(&1, "type") |> hd()))
      assert types == ["image/avif", "image/webp"]

      # The first source's srcset embeds format=avif.
      avif_source = Enum.at(sources, 0)
      [avif_srcset] = Floki.attribute(avif_source, "srcset")
      assert avif_srcset =~ "format=avif"

      # The fallback <img> exists inside the <picture>.
      [_img] = Floki.find(doc, "picture > img")
    end

    test "with empty formats renders bare <img>" do
      html =
        r(%{
          src: "/p.jpg",
          alt: "p",
          width: 800,
          height: 600,
          sizes: "100vw"
        })

      doc = parse(html)
      assert Floki.find(doc, "picture") == []
      assert length(Floki.find(doc, "img")) == 1
    end
  end

  describe "priority + loading" do
    test "priority=:lcp promotes loading=eager and adds fetchpriority=high" do
      html =
        r(%{
          src: "/hero.jpg",
          alt: "h",
          width: 1600,
          height: 900,
          priority: :lcp,
          sizes: "100vw"
        })

      [img] = parse(html) |> Floki.find("img")
      assert Floki.attribute(img, "loading") == ["eager"]
      assert Floki.attribute(img, "fetchpriority") == ["high"]
    end

    test "default priority is loading=lazy without fetchpriority" do
      html =
        r(%{src: "/x.jpg", alt: "x", width: 800, height: 600, sizes: "100vw"})

      [img] = parse(html) |> Floki.find("img")
      assert Floki.attribute(img, "loading") == ["lazy"]
      assert Floki.attribute(img, "fetchpriority") == []
    end

    test "explicit loading=eager honours user choice" do
      html =
        r(%{src: "/x.jpg", alt: "x", width: 800, height: 600, sizes: "100vw", loading: :eager})

      [img] = parse(html) |> Floki.find("img")
      assert Floki.attribute(img, "loading") == ["eager"]
      assert Floki.attribute(img, "fetchpriority") == []
    end
  end

  describe "host + mount + scheme" do
    test "host renders absolute URLs with the configured scheme" do
      html =
        r(%{
          src: "/x.jpg",
          alt: "x",
          width: 800,
          height: 600,
          sizes: "100vw",
          host: "img.example.com"
        })

      [img] = parse(html) |> Floki.find("img")
      [src] = Floki.attribute(img, "src")
      assert String.starts_with?(src, "https://img.example.com/cdn-cgi/image/")
    end

    test "mount prefixes the path" do
      html =
        r(%{
          src: "/x.jpg",
          alt: "x",
          width: 800,
          height: 600,
          sizes: "100vw",
          mount: "/img"
        })

      [img] = parse(html) |> Floki.find("img")
      [src] = Floki.attribute(img, "src")
      assert String.starts_with?(src, "/img/cdn-cgi/image/")
    end
  end

  describe "url_options pass-through" do
    test "extra options apply to every URL in the srcset" do
      html =
        r(%{
          src: "/x.jpg",
          alt: "x",
          width: 800,
          height: 600,
          sizes: "100vw",
          url_options: [fit: :cover, quality: 75]
        })

      [img] = parse(html) |> Floki.find("img")
      [srcset] = Floki.attribute(img, "srcset")

      # Every entry in the srcset should carry fit=cover,quality=75.
      entries = String.split(srcset, ", ")
      assert Enum.all?(entries, &(&1 =~ "fit=cover"))
      assert Enum.all?(entries, &(&1 =~ "quality=75"))
    end
  end
end
