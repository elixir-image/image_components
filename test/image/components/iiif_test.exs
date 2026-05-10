defmodule Image.Components.IIIFTest do
  @moduledoc """
  Unit tests for `Image.Components.URL.iiif/2`. Covers the five
  positional URL segments — region / size / rotation / quality /
  format — plus identifier encoding and the documented conformance
  gaps (`fit: :cover`, effects, vignette, tint, face_zoom dropped).

  Tagged `:iiif`; included in the default suite.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Image.Components.URL
  alias Image.Plug.Pipeline
  alias Image.Plug.Pipeline.Ops

  @moduletag :iiif

  describe "default URL shape" do
    test "empty pipeline → /full/max/0/default.jpg" do
      assert URL.iiif(%Pipeline{ops: [], output: nil}, source_path: "/cat.jpg") ==
               "/iiif/3/cat.jpg/full/max/0/default.jpg"
    end

    test "host is prepended verbatim" do
      url =
        URL.iiif(%Pipeline{ops: [], output: nil},
          source_path: "/cat.jpg",
          host: "https://iiif.example.org"
        )

      assert url == "https://iiif.example.org/iiif/3/cat.jpg/full/max/0/default.jpg"
    end

    test ":iiif_prefix overrides the default" do
      url =
        URL.iiif(%Pipeline{ops: [], output: nil},
          source_path: "/cat.jpg",
          iiif_prefix: "/cantaloupe/iiif/3"
        )

      assert url == "/cantaloupe/iiif/3/cat.jpg/full/max/0/default.jpg"
    end
  end

  describe "identifier encoding" do
    test "leading slash is stripped" do
      url = URL.iiif(%Pipeline{ops: [], output: nil}, source_path: "/cat.jpg")
      assert url =~ "/iiif/3/cat.jpg/"
    end

    test "embedded slashes are percent-encoded as %2F" do
      url = URL.iiif(%Pipeline{ops: [], output: nil}, source_path: "/sub/cat.jpg")
      assert url =~ "/iiif/3/sub%2Fcat.jpg/"
    end

    test "spaces and reserved chars are percent-encoded" do
      url = URL.iiif(%Pipeline{ops: [], output: nil}, source_path: "/sub dir/cat&dog.jpg")
      assert url =~ "/iiif/3/sub%20dir%2Fcat%26dog.jpg/"
    end
  end

  describe "size segment" do
    test "width only → w," do
      pipeline = %Pipeline{ops: [%Ops.Resize{width: 600, upscale?: false}], output: nil}
      assert URL.iiif(pipeline, source_path: "/x.jpg") =~ "/full/600,/0/"
    end

    test "height only → ,h" do
      pipeline = %Pipeline{ops: [%Ops.Resize{height: 400, upscale?: false}], output: nil}
      assert URL.iiif(pipeline, source_path: "/x.jpg") =~ "/full/,400/0/"
    end

    test "fit: :contain → !w,h" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 600, height: 400, fit: :contain, upscale?: false}],
        output: nil
      }

      assert URL.iiif(pipeline, source_path: "/x.jpg") =~ "/full/!600,400/0/"
    end

    test "fit: :squeeze → w,h (distort)" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 600, height: 400, fit: :squeeze, upscale?: false}],
        output: nil
      }

      assert URL.iiif(pipeline, source_path: "/x.jpg") =~ "/full/600,400/0/"
    end

    test "upscale?: true prepends ^" do
      pipeline = %Pipeline{ops: [%Ops.Resize{width: 600, upscale?: true}], output: nil}
      assert URL.iiif(pipeline, source_path: "/x.jpg") =~ "/full/^600,/0/"
    end

    test "no Resize → max" do
      assert URL.iiif(%Pipeline{ops: [], output: nil}, source_path: "/x.jpg") =~ "/full/max/0/"
    end
  end

  describe "rotation segment" do
    test "Rotate{angle: 0} → 0" do
      pipeline = %Pipeline{ops: [%Ops.Rotate{angle: 0}], output: nil}
      assert URL.iiif(pipeline, source_path: "/x.jpg") =~ "/full/max/0/"
    end

    test "Rotate{angle: 90} → 90" do
      pipeline = %Pipeline{ops: [%Ops.Rotate{angle: 90}], output: nil}
      assert URL.iiif(pipeline, source_path: "/x.jpg") =~ "/full/max/90/"
    end

    test "Rotate{angle: 45} → 45 (arbitrary angles allowed in 3.0)" do
      pipeline = %Pipeline{ops: [%Ops.Rotate{angle: 45}], output: nil}
      assert URL.iiif(pipeline, source_path: "/x.jpg") =~ "/full/max/45/"
    end
  end

  describe "quality segment" do
    test "Adjust{saturation: 0.0} → gray" do
      pipeline = %Pipeline{ops: [%Ops.Adjust{saturation: 0.0}], output: nil}
      assert URL.iiif(pipeline, source_path: "/x.jpg") =~ "/0/gray.jpg"
    end

    test "Posterize{levels: 2} → bitonal" do
      pipeline = %Pipeline{ops: [%Ops.Posterize{levels: 2}], output: nil}
      assert URL.iiif(pipeline, source_path: "/x.jpg") =~ "/0/bitonal.jpg"
    end

    test "no quality-implying op → default" do
      assert URL.iiif(%Pipeline{ops: [], output: nil}, source_path: "/x.jpg") =~ "/0/default.jpg"
    end
  end

  describe "format extension" do
    test ":jpeg → .jpg" do
      pipeline = %Pipeline{ops: [], output: %Ops.Format{type: :jpeg, quality: 80}}
      assert URL.iiif(pipeline, source_path: "/x.jpg") =~ "default.jpg"
    end

    test ":webp → .webp" do
      pipeline = %Pipeline{ops: [], output: %Ops.Format{type: :webp, quality: 80}}
      assert URL.iiif(pipeline, source_path: "/x.jpg") =~ "default.webp"
    end

    test ":tiff → .tif" do
      pipeline = %Pipeline{ops: [], output: %Ops.Format{type: :tiff, quality: 80}}
      assert URL.iiif(pipeline, source_path: "/x.jpg") =~ "default.tif"
    end

    test ":auto + :iiif_format option → falls back to the option" do
      pipeline = %Pipeline{ops: [], output: %Ops.Format{type: :auto, quality: 80}}
      url = URL.iiif(pipeline, source_path: "/x.jpg", iiif_format: :png)
      assert url =~ "default.png"
    end

    test ":auto with no :iiif_format option → falls back to .jpg" do
      pipeline = %Pipeline{ops: [], output: %Ops.Format{type: :auto, quality: 80}}
      assert URL.iiif(pipeline, source_path: "/x.jpg") =~ "default.jpg"
    end
  end

  describe "documented conformance gaps (silently dropped)" do
    test "Blur is dropped" do
      pipeline = %Pipeline{ops: [%Ops.Blur{sigma: 5.0}], output: nil}
      url = URL.iiif(pipeline, source_path: "/x.jpg")
      refute url =~ "blur"
      assert url =~ "/full/max/0/default.jpg"
    end

    test "Vignette is dropped" do
      pipeline = %Pipeline{ops: [%Ops.Vignette{strength: 0.6}], output: nil}
      url = URL.iiif(pipeline, source_path: "/x.jpg")
      refute url =~ "vignette"
    end

    test "Tint is dropped" do
      pipeline = %Pipeline{ops: [%Ops.Tint{color: [128, 80, 200]}], output: nil}
      url = URL.iiif(pipeline, source_path: "/x.jpg")
      refute url =~ "tint"
      refute url =~ "monochrome"
    end

    test "Resize.face_zoom is dropped" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 600, gravity: :face, face_zoom: 0.7}],
        output: nil
      }

      url = URL.iiif(pipeline, source_path: "/x.jpg")
      refute url =~ "face"
      refute url =~ "zoom"
    end

    test "non-grayscale Adjust is dropped — quality stays default" do
      pipeline = %Pipeline{
        ops: [%Ops.Adjust{brightness: 1.4, contrast: 1.2, saturation: 1.0, gamma: 1.0}],
        output: nil
      }

      assert URL.iiif(pipeline, source_path: "/x.jpg") =~ "/0/default.jpg"
    end
  end

  describe "properties" do
    property "every URL has exactly 5 segments after the prefix" do
      check all width <- one_of([constant(nil), integer(50..2000)]),
                height <- one_of([constant(nil), integer(50..2000)]),
                rotate <- integer(0..360),
                upscale? <- boolean(),
                format <- member_of([:auto, :jpeg, :png, :webp, :avif, :tiff, :jp2]) do
        pipeline = %Pipeline{
          ops: [
            %Ops.Resize{width: width, height: height, fit: :contain, upscale?: upscale?},
            %Ops.Rotate{angle: rotate}
          ],
          output: %Ops.Format{type: format, quality: 80}
        }

        url = URL.iiif(pipeline, source_path: "/x.jpg")

        # /iiif/3/<id>/<region>/<size>/<rotation>/<quality>.<format>
        # → 7 leading segments after splitting on /
        segments = url |> String.trim_leading("/") |> String.split("/")
        assert length(segments) == 7, "expected 7 path components in #{url}"
      end
    end

    property "identifier always lands at the right position" do
      check all path <- one_of([
                  constant("/cat.jpg"),
                  constant("/sub/cat.jpg"),
                  constant("/sub dir/cat&dog.jpg"),
                  constant("/01234.tif")
                ]) do
        url = URL.iiif(%Pipeline{ops: [], output: nil}, source_path: path)

        # The identifier is the third segment (`iiif`, `3`, identifier).
        ["", "iiif", "3", id | _rest] = String.split(url, "/")

        # Identifier must round-trip: decoding it must reproduce the
        # original (less the leading `/`).
        assert URI.decode(id) == String.trim_leading(path, "/")
      end
    end
  end
end
