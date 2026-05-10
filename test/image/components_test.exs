defmodule Image.ComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Image.Components
  alias Image.Plug.Pipeline.Ops

  doctest Components

  describe "build_pipeline/1" do
    test "empty assigns → empty Pipeline" do
      pipeline = Components.build_pipeline(%{})
      assert pipeline.ops == []
      assert pipeline.output == nil
    end

    test "resize fields populate Ops.Resize" do
      pipeline =
        Components.build_pipeline(%{
          width: 600,
          height: 400,
          fit: :cover,
          gravity: :face,
          dpr: 2,
          face_zoom: 0.6
        })

      assert [%Ops.Resize{} = resize] = pipeline.ops
      assert resize.width == 600
      assert resize.height == 400
      assert resize.fit == :cover
      assert resize.gravity == :face
      assert resize.dpr == 2
      assert resize.face_zoom == 0.6
    end

    test "format and quality populate Ops.Format" do
      pipeline = Components.build_pipeline(%{format: :webp, quality: 80})
      assert pipeline.output == %Ops.Format{type: :webp, quality: 80}
    end

    test "blur sigma > 0 prepends Ops.Blur" do
      pipeline = Components.build_pipeline(%{blur: 4.5})
      assert Enum.find(pipeline.ops, &match?(%Ops.Blur{sigma: 4.5}, &1))
    end

    test "blur sigma == 0 does not add an Ops.Blur" do
      pipeline = Components.build_pipeline(%{blur: 0})
      refute Enum.any?(pipeline.ops, &match?(%Ops.Blur{}, &1))
    end

    test "tint accepts hex string and normalises to [r, g, b]" do
      pipeline = Components.build_pipeline(%{tint: "#80a0c0"})
      assert [%Ops.Tint{color: [128, 160, 192]}] = pipeline.ops
    end

    test "tint accepts hex string without leading #" do
      pipeline = Components.build_pipeline(%{tint: "ff0000"})
      assert [%Ops.Tint{color: [255, 0, 0]}] = pipeline.ops
    end

    test "tint accepts already-RGB list" do
      pipeline = Components.build_pipeline(%{tint: [10, 20, 30]})
      assert [%Ops.Tint{color: [10, 20, 30]}] = pipeline.ops
    end

    test "tint with garbage value is silently dropped" do
      pipeline = Components.build_pipeline(%{tint: "not a colour"})
      assert pipeline.ops == []
    end

    test "vignette > 0 prepends Ops.Vignette" do
      pipeline = Components.build_pipeline(%{vignette: 0.6})
      assert Enum.find(pipeline.ops, &match?(%Ops.Vignette{strength: 0.6}, &1))
    end

    test "vignette == 0 does not add an Ops.Vignette" do
      pipeline = Components.build_pipeline(%{vignette: 0})
      refute Enum.any?(pipeline.ops, &match?(%Ops.Vignette{}, &1))
    end
  end

  describe "image/1 render" do
    test "renders an <img> with the projected URL" do
      assigns = %{}

      html =
        ~H"""
        <Image.Components.image src="/cat.jpg" provider={:cloudflare} width={200} />
        """
        |> rendered_to_string()

      assert html =~ ~s(<img )
      assert html =~ ~s(src="/cdn-cgi/image/width=200/cat.jpg")
    end

    test "honors :host" do
      html =
        render_component(&Components.image/1,
          src: "/cat.jpg",
          provider: :imgix,
          host: "https://my.imgix.net",
          width: 100
        )

      assert html =~ ~s(src="https://my.imgix.net/cat.jpg?w=100")
    end

    test "passes through HTML attributes via :rest" do
      html =
        render_component(&Components.image/1,
          src: "/cat.jpg",
          provider: :cloudflare,
          alt: "a cat",
          class: "thumb"
        )

      assert html =~ ~s(alt="a cat")
      assert html =~ ~s(class="thumb")
    end
  end

  describe "picture/1 render" do
    test "emits one <source> per format plus a fallback <img>" do
      html =
        render_component(&Components.picture/1,
          src: "/cat.jpg",
          provider: :cloudflare,
          formats: [:avif, :webp],
          width: 600
        )

      assert html =~ ~s(<picture>)
      assert html =~ ~s(<source type="image/avif")
      assert html =~ ~s(<source type="image/webp")
      assert html =~ ~s(<img )
    end

    test "<source> srcset URLs include their format" do
      html =
        render_component(&Components.picture/1,
          src: "/cat.jpg",
          provider: :cloudflare,
          formats: [:avif],
          width: 600
        )

      assert html =~ ~r{srcset="[^"]*format=avif[^"]*"}
    end
  end

  defp rendered_to_string(rendered) do
    rendered
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
