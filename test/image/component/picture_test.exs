defmodule Image.Component.PictureTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  defp r(assigns), do: render_component(&Image.Component.Picture.picture/1, assigns)
  defp parse(html), do: Floki.parse_fragment!(html)

  defp basic_assigns do
    %{
      alt: "Founder portrait",
      sources: [
        %{
          media: "(min-width: 1024px)",
          src: "/founder.jpg",
          width: 1200,
          height: 800,
          sizes: "1200px",
          formats: [:avif, :webp],
          url_options: [fit: :cover, gravity: :face]
        },
        %{
          media: "(min-width: 480px)",
          src: "/founder.jpg",
          width: 800,
          height: 1000,
          sizes: "100vw",
          formats: [:avif, :webp],
          url_options: [fit: :cover, gravity: :face]
        }
      ],
      fallback: %{
        src: "/founder.jpg",
        width: 480,
        height: 600,
        sizes: "100vw",
        url_options: [fit: :cover, gravity: :face]
      }
    }
  end

  test "renders a <picture> with a <source> per format per breakpoint plus a fallback <img>" do
    html = r(basic_assigns())
    doc = parse(html)

    sources = Floki.find(doc, "picture > source")

    # 2 breakpoints x 2 formats = 4 sources.
    assert length(sources) == 4

    # The first source is the largest (1024px+) AVIF entry.
    first = Enum.at(sources, 0)
    assert Floki.attribute(first, "media") == ["(min-width: 1024px)"]
    assert Floki.attribute(first, "type") == ["image/avif"]
    [first_srcset] = Floki.attribute(first, "srcset")
    assert first_srcset =~ "format=avif"
    assert first_srcset =~ "fit=cover"
    assert first_srcset =~ "gravity=face"

    # Fallback <img> is the last child.
    [img] = Floki.find(doc, "picture > img")
    assert Floki.attribute(img, "alt") == ["Founder portrait"]
    assert Floki.attribute(img, "width") == ["480"]
    assert Floki.attribute(img, "height") == ["600"]
    assert Floki.attribute(img, "decoding") == ["async"]
  end

  test "media-query order on the <source> elements matches the input order" do
    html = r(basic_assigns())
    sources = parse(html) |> Floki.find("picture > source")

    medias =
      sources
      |> Enum.map(&(Floki.attribute(&1, "media") |> hd()))
      |> Enum.uniq()

    assert medias == ["(min-width: 1024px)", "(min-width: 480px)"]
  end

  test "priority=:lcp is honoured on the fallback <img>" do
    assigns = Map.put(basic_assigns(), :priority, :lcp)
    [img] = r(assigns) |> parse() |> Floki.find("picture > img")

    assert Floki.attribute(img, "loading") == ["eager"]
    assert Floki.attribute(img, "fetchpriority") == ["high"]
  end

  test "host applies to every source URL and the fallback URL" do
    assigns = Map.put(basic_assigns(), :host, "img.example.com")
    doc = parse(r(assigns))

    [img] = Floki.find(doc, "picture > img")
    assert Floki.attribute(img, "src") |> hd() |> String.starts_with?("https://img.example.com/")

    sources = Floki.find(doc, "picture > source")
    Enum.each(sources, fn source ->
      [srcset] = Floki.attribute(source, "srcset")

      Enum.each(String.split(srcset, ", "), fn entry ->
        [url, _descriptor] = String.split(entry, " ")
        assert String.starts_with?(url, "https://img.example.com/")
      end)
    end)
  end
end
