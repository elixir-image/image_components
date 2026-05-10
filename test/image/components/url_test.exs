defmodule Image.Components.URLTest do
  use ExUnit.Case, async: true

  alias Image.Components.URL
  alias Image.Plug.Pipeline
  alias Image.Plug.Pipeline.Ops

  doctest URL

  describe "default-trimming" do
    test "no resize op + nil output → Cloudflare emits format=auto fallback" do
      assert URL.cloudflare(%Pipeline{ops: [], output: nil}, source_path: "/x.jpg") ==
               "/cdn-cgi/image/format=auto/x.jpg"
    end

    test "Cloudflare default fit/gravity are skipped" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 200, fit: :contain, gravity: :center}],
        output: nil
      }

      assert URL.cloudflare(pipeline, source_path: "/x.jpg") ==
               "/cdn-cgi/image/width=200/x.jpg"
    end

    test "Cloudinary default fit (fit) and gravity (center) are skipped" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 200, fit: :contain, gravity: :center}],
        output: nil
      }

      assert URL.cloudinary(pipeline, source_path: "/x.jpg") ==
               "/demo/image/upload/w_200/x.jpg"
    end

    test "imgix default fit (clip) is skipped" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 200, fit: :contain}],
        output: nil
      }

      assert URL.imgix(pipeline, source_path: "/x.jpg") == "/x.jpg?w=200"
    end

    test "ImageKit default fit (maintain_ratio) and focus (center) are skipped" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 200, fit: :contain, gravity: :center}],
        output: nil
      }

      assert URL.imagekit(pipeline, source_path: "/x.jpg") == "/demo/tr:w-200/x.jpg"
    end
  end

  describe "adjust ops — Cloudflare uses raw multipliers, others centred percentages" do
    setup do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 400}, %Ops.Adjust{contrast: 1.4}],
        output: nil
      }

      {:ok, pipeline: pipeline}
    end

    test "Cloudflare emits the raw multiplier", %{pipeline: pipeline} do
      assert URL.cloudflare(pipeline, source_path: "/x.jpg") =~ "contrast=1.4"
      refute URL.cloudflare(pipeline, source_path: "/x.jpg") =~ "contrast=40"
    end

    test "Cloudinary emits centred percentage as e_contrast:N", %{pipeline: pipeline} do
      assert URL.cloudinary(pipeline, source_path: "/x.jpg") =~ "e_contrast:40"
    end

    test "imgix emits centred percentage as con=N", %{pipeline: pipeline} do
      assert URL.imgix(pipeline, source_path: "/x.jpg") =~ "con=40"
    end

    test "ImageKit URL grammar has no parameterised contrast — silently dropped",
         %{pipeline: pipeline} do
      url = URL.imagekit(pipeline, source_path: "/x.jpg")
      refute url =~ "contrast"
      refute url =~ "e-contrast"
    end
  end

  describe "blur / sharpen scaling per provider" do
    test "Cloudflare: blur sigma 5.0 → blur=10 (×2)" do
      pipeline = %Pipeline{ops: [%Ops.Blur{sigma: 5.0}], output: nil}
      assert URL.cloudflare(pipeline, source_path: "/x.jpg") =~ "blur=10"
    end

    test "Cloudinary: blur sigma 5.0 → e_blur:500 (×100)" do
      pipeline = %Pipeline{ops: [%Ops.Blur{sigma: 5.0}], output: nil}
      assert URL.cloudinary(pipeline, source_path: "/x.jpg") =~ "e_blur:500"
    end

    test "imgix: blur sigma 5.0 → blur=500 (×100)" do
      pipeline = %Pipeline{ops: [%Ops.Blur{sigma: 5.0}], output: nil}
      assert URL.imgix(pipeline, source_path: "/x.jpg") =~ "blur=500"
    end

    test "ImageKit: blur sigma 5.0 → e-blur-500 (×100)" do
      pipeline = %Pipeline{ops: [%Ops.Blur{sigma: 5.0}], output: nil}
      assert URL.imagekit(pipeline, source_path: "/x.jpg") =~ "e-blur-500"
    end
  end

  describe "face_zoom is expressible only in CDNs whose URL grammar supports it" do
    setup do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 400, fit: :cover, gravity: :face, face_zoom: 0.7}],
        output: nil
      }

      {:ok, pipeline: pipeline}
    end

    test "Cloudflare emits face-zoom=0.7", %{pipeline: pipeline} do
      assert URL.cloudflare(pipeline, source_path: "/x.jpg") =~ "face-zoom=0.7"
    end

    test "Cloudinary emits z_0.7", %{pipeline: pipeline} do
      assert URL.cloudinary(pipeline, source_path: "/x.jpg") =~ "z_0.7"
    end

    test "ImageKit emits z-0.7", %{pipeline: pipeline} do
      assert URL.imagekit(pipeline, source_path: "/x.jpg") =~ "z-0.7"
    end

    test "imgix has no face-zoom parameter — silently dropped", %{pipeline: pipeline} do
      url = URL.imgix(pipeline, source_path: "/x.jpg")
      refute url =~ "facepad"
      refute url =~ "face-zoom"
    end
  end

  describe "vignette is expressible only in Cloudinary's URL grammar" do
    setup do
      pipeline = %Pipeline{ops: [%Ops.Vignette{strength: 0.6}], output: nil}
      {:ok, pipeline: pipeline}
    end

    test "Cloudinary emits e_vignette:60", %{pipeline: pipeline} do
      assert URL.cloudinary(pipeline, source_path: "/x.jpg") =~ "e_vignette:60"
    end

    test "Cloudflare drops vignette", %{pipeline: pipeline} do
      refute URL.cloudflare(pipeline, source_path: "/x.jpg") =~ "vignette"
    end

    test "imgix drops vignette", %{pipeline: pipeline} do
      refute URL.imgix(pipeline, source_path: "/x.jpg") =~ "vignette"
    end

    test "ImageKit drops vignette", %{pipeline: pipeline} do
      refute URL.imagekit(pipeline, source_path: "/x.jpg") =~ "vignette"
    end
  end

  describe "tint is expressible only as imgix monochrome" do
    setup do
      pipeline = %Pipeline{ops: [%Ops.Tint{color: [128, 80, 200]}], output: nil}
      {:ok, pipeline: pipeline}
    end

    test "imgix emits monochrome=8050c8", %{pipeline: pipeline} do
      url = URL.imgix(pipeline, source_path: "/x.jpg")
      assert url =~ "monochrome=8050c8"
    end

    test "Cloudflare drops tint", %{pipeline: pipeline} do
      refute URL.cloudflare(pipeline, source_path: "/x.jpg") =~ "monochrome"
      refute URL.cloudflare(pipeline, source_path: "/x.jpg") =~ "tint"
    end

    test "Cloudinary drops tint", %{pipeline: pipeline} do
      refute URL.cloudinary(pipeline, source_path: "/x.jpg") =~ "monochrome"
    end

    test "ImageKit drops tint", %{pipeline: pipeline} do
      refute URL.imagekit(pipeline, source_path: "/x.jpg") =~ "monochrome"
    end
  end

  describe ":host is prepended verbatim" do
    test "Cloudflare with /img mount prefix" do
      pipeline = %Pipeline{ops: [%Ops.Resize{width: 200}], output: nil}

      assert URL.cloudflare(pipeline, source_path: "/x.jpg", host: "/img") ==
               "/img/cdn-cgi/image/width=200/x.jpg"
    end

    test "imgix accepts an absolute host" do
      pipeline = %Pipeline{ops: [%Ops.Resize{width: 200}], output: nil}

      assert URL.imgix(pipeline, source_path: "/x.jpg", host: "https://my.imgix.net") ==
               "https://my.imgix.net/x.jpg?w=200"
    end
  end

  describe "Cloudinary :cloudinary_account / ImageKit :imagekit_endpoint overrides" do
    test "Cloudinary uses :cloudinary_account when supplied" do
      pipeline = %Pipeline{ops: [], output: nil}

      assert URL.cloudinary(pipeline, source_path: "/x.jpg", cloudinary_account: "my-cloud") ==
               "/my-cloud/image/upload/x.jpg"
    end

    test "ImageKit uses :imagekit_endpoint when supplied" do
      pipeline = %Pipeline{ops: [], output: nil}

      assert URL.imagekit(pipeline, source_path: "/x.jpg", imagekit_endpoint: "my-account") ==
               "/my-account/x.jpg"
    end
  end
end
