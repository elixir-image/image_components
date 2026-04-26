defmodule Image.Component.SrcsetTest do
  use ExUnit.Case, async: true
  doctest Image.Component.Srcset

  alias Image.Component.{Layout, Srcset}

  describe "build/3 with width-descriptor layout" do
    test "emits one srcset entry per width with a `Nw` descriptor" do
      layout = Layout.compute(:constrained, 800, 600, widths: [400, 800])
      result = Srcset.build("/x.jpg", layout)

      assert result =~ "/cdn-cgi/image/width=400/x.jpg 400w"
      assert result =~ "/cdn-cgi/image/width=800/x.jpg 800w"
    end

    test "url_options apply to every entry but :width is overridden per-width" do
      layout = Layout.compute(:constrained, 800, 600, widths: [400, 800])

      result =
        Srcset.build("/x.jpg", layout,
          url_options: [format: :webp, width: 99_999]
        )

      assert result =~ "format=webp"
      refute result =~ "width=99999"
    end
  end

  describe "build/3 with density-descriptor layout" do
    test "emits one entry per DPR factor with `Nx` descriptor" do
      layout = Layout.compute(:fixed, 100, 100, dpr_factors: [1, 2, 3])
      result = Srcset.build("/icon.png", layout)

      assert result =~ "/cdn-cgi/image/width=100/icon.png 1x"
      assert result =~ "/cdn-cgi/image/width=200/icon.png 2x"
      assert result =~ "/cdn-cgi/image/width=300/icon.png 3x"
    end
  end

  describe "per_format/3" do
    test "produces a keyword list in the requested format order" do
      layout = Layout.compute(:constrained, 800, 600, widths: [400])
      result = Srcset.per_format("/x.jpg", layout, formats: [:avif, :webp])

      assert Keyword.keys(result) == [:avif, :webp]
      assert result[:avif] =~ "format=avif"
      assert result[:webp] =~ "format=webp"
    end

    test ":format is enforced per entry, overriding any :format in :url_options" do
      layout = Layout.compute(:constrained, 800, 600, widths: [400])

      result =
        Srcset.per_format("/x.jpg", layout,
          formats: [:avif],
          url_options: [format: :png, fit: :cover]
        )

      assert result[:avif] =~ "format=avif"
      refute result[:avif] =~ "format=png"
      assert result[:avif] =~ "fit=cover"
    end
  end

  describe "mime_type/1" do
    test "documented format atoms map to MIME types" do
      assert Srcset.mime_type(:avif) == "image/avif"
      assert Srcset.mime_type(:webp) == "image/webp"
      assert Srcset.mime_type(:jpeg) == "image/jpeg"
      assert Srcset.mime_type(:baseline_jpeg) == "image/jpeg"
      assert Srcset.mime_type(:png) == "image/png"
    end
  end
end
