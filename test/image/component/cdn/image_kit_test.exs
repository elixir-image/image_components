defmodule Image.Component.CDN.ImageKitTest do
  use ExUnit.Case, async: true
  doctest Image.Component.CDN.ImageKit.URL

  alias Image.Component.CDN
  alias Image.Component.CDN.ImageKit.URL

  describe "atom shorthand" do
    test ":image_kit resolves to the ImageKit adapter" do
      assert {Image.Component.CDN.ImageKit, []} = CDN.resolve(:image_kit)
    end
  end

  describe "URL.build/2" do
    test "no options yields just the source path" do
      assert URL.build("/sample.jpg") == "/sample.jpg"
    end

    test "single option yields tr:<key>-<value>" do
      assert URL.build("/sample.jpg", width: 800) == "/tr:w-800/sample.jpg"
    end

    test "options sorted alphabetically (cache-friendly)" do
      assert URL.build("/p.jpg", width: 800, fit: :cover, format: :webp) ==
               "/tr:c-extract,f-webp,w-800/p.jpg"
    end

    test "host produces an https origin" do
      assert URL.build("/p.jpg", host: "ik.imagekit.io", width: 200) ==
               "https://ik.imagekit.io/tr:w-200/p.jpg"
    end

    test "endpoint sits between host and tr:" do
      assert URL.build("/p.jpg",
               host: "ik.imagekit.io",
               endpoint: "your_id",
               width: 200
             ) == "https://ik.imagekit.io/your_id/tr:w-200/p.jpg"
    end

    test "fit translates to imagekit vocabulary" do
      assert URL.build("/p.jpg", fit: :contain) == "/tr:c-maintain_ratio/p.jpg"
      assert URL.build("/p.jpg", fit: :cover) == "/tr:c-extract/p.jpg"
      assert URL.build("/p.jpg", fit: :pad) == "/tr:c-pad_resize/p.jpg"
      assert URL.build("/p.jpg", fit: :scale_down) == "/tr:c-at_max/p.jpg"
      assert URL.build("/p.jpg", fit: :squeeze) == "/tr:c-force/p.jpg"
    end

    test "format translates to imagekit vocabulary" do
      assert URL.build("/p.jpg", format: :jpeg) == "/tr:f-jpg/p.jpg"
      assert URL.build("/p.jpg", format: :auto) == "/tr:f-auto/p.jpg"
      assert URL.build("/p.jpg", format: :webp) == "/tr:f-webp/p.jpg"
    end

    test "gravity translates to imagekit fo- vocabulary" do
      assert URL.build("/p.jpg", gravity: :north) == "/tr:fo-top/p.jpg"
      assert URL.build("/p.jpg", gravity: :face) == "/tr:fo-face/p.jpg"
      assert URL.build("/p.jpg", gravity: :north_west) == "/tr:fo-top_left/p.jpg"
    end

    test "{:xy, x, y} gravity emits fo-custom + x-/y-" do
      assert URL.build("/p.jpg", gravity: {:xy, 0.25, 0.75}) ==
               "/tr:fo-custom,x-0.25,y-0.75/p.jpg"
    end

    test "background strips leading # if present" do
      assert URL.build("/p.jpg", background: "#ff0000") == "/tr:bg-ff0000/p.jpg"
      assert URL.build("/p.jpg", background: "ff0000") == "/tr:bg-ff0000/p.jpg"
    end

    test "blur scales by 100" do
      assert URL.build("/p.jpg", blur: 5.0) == "/tr:e-blur-500/p.jpg"
    end

    test "sharpen scales by 10" do
      assert URL.build("/p.jpg", sharpen: 5.0) == "/tr:e-sharpen-50/p.jpg"
    end
  end

  describe "round-trip with the server-side parser" do
    test "every URL the client builds parses cleanly on the server" do
      cases = [
        [width: 800],
        [width: 800, height: 600, fit: :cover],
        [width: 400, format: :webp, quality: 80],
        [width: 200, gravity: :face, fit: :cover]
      ]

      for opts <- cases do
        url = URL.build("/photo.jpg", opts)
        # url is "/tr:<transforms>/photo.jpg"; extract the
        # transform string and feed to the server parser.
        ["", "tr:" <> transforms, _source] = String.split(url, "/", parts: 3)

        assert {:ok, %Image.Plug.Pipeline{}} =
                 Image.Plug.Provider.ImageKit.Options.parse(transforms),
               "client-built URL #{inspect(url)} did not parse on the server"
      end
    end

    test "signed URL: client signs, server verifies" do
      url = URL.build("/photo.jpg", width: 200, format: :jpeg, signing_keys: ["test-key"])

      assert :ok =
               Image.Plug.Provider.ImageKit.Signing.verify(
                 url,
                 ["test-key"],
                 required?: true
               )
    end
  end
end
