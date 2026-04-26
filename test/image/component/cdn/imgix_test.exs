defmodule Image.Component.CDN.ImgixTest do
  use ExUnit.Case, async: true
  doctest Image.Component.CDN.Imgix.URL
  doctest Image.Component.CDN.Imgix.Signing

  alias Image.Component.CDN
  alias Image.Component.CDN.Imgix.URL

  describe "atom shorthand" do
    test ":imgix resolves to the Imgix adapter" do
      assert {Image.Component.CDN.Imgix, []} = CDN.resolve(:imgix)
    end
  end

  describe "URL.build/2" do
    test "no options yields just the source path" do
      assert URL.build("/photo.jpg") == "/photo.jpg"
    end

    test "single option yields ?key=value" do
      assert URL.build("/photo.jpg", width: 800) == "/photo.jpg?w=800"
    end

    test "options sorted alphabetically (cache-friendly)" do
      assert URL.build("/p.jpg", width: 800, fit: :cover, format: :webp) ==
               "/p.jpg?fit=crop&fm=webp&w=800"
    end

    test "host produces an https origin" do
      assert URL.build("/p.jpg", host: "example.imgix.net", width: 200) ==
               "https://example.imgix.net/p.jpg?w=200"
    end

    test "fit translates to imgix vocabulary" do
      assert URL.build("/p.jpg", fit: :contain) == "/p.jpg?fit=clip"
      assert URL.build("/p.jpg", fit: :cover) == "/p.jpg?fit=crop"
      assert URL.build("/p.jpg", fit: :pad) == "/p.jpg?fit=fill"
      assert URL.build("/p.jpg", fit: :scale_down) == "/p.jpg?fit=max"
      assert URL.build("/p.jpg", fit: :squeeze) == "/p.jpg?fit=scale"
    end

    test "format translates to imgix vocabulary" do
      assert URL.build("/p.jpg", format: :jpeg) == "/p.jpg?fm=jpg"
      assert URL.build("/p.jpg", format: :auto) == "/p.jpg?auto=format"
      assert URL.build("/p.jpg", format: :baseline_jpeg) == "/p.jpg?fm=pjpg"
    end

    test "gravity translates to imgix crop= vocabulary" do
      assert URL.build("/p.jpg", gravity: :north) == "/p.jpg?crop=top"
      assert URL.build("/p.jpg", gravity: :face) == "/p.jpg?crop=faces"
      assert URL.build("/p.jpg", gravity: :north_west) == "/p.jpg?crop=top,left"
    end

    test "{:xy, x, y} gravity emits crop=focalpoint + fp-x + fp-y" do
      assert URL.build("/p.jpg", gravity: {:xy, 0.25, 0.75}) ==
               "/p.jpg?crop=focalpoint&fp-x=0.25&fp-y=0.75"
    end

    test "background strips leading # if present" do
      assert URL.build("/p.jpg", background: "#ff0000") == "/p.jpg?bg=ff0000"
      assert URL.build("/p.jpg", background: "ff0000") == "/p.jpg?bg=ff0000"
    end

    test "blur scales by 100" do
      assert URL.build("/p.jpg", blur: 5.0) == "/p.jpg?blur=500"
    end

    test "sharpen scales by 10" do
      assert URL.build("/p.jpg", sharpen: 5.0) == "/p.jpg?sharp=50"
    end

    test "adjust multipliers map to -100..100" do
      assert URL.build("/p.jpg", brightness: 1.2) == "/p.jpg?bri=20"
      assert URL.build("/p.jpg", saturation: 0.5) == "/p.jpg?sat=-50"
    end

    test "absolute https source becomes a percent-encoded path segment (web-proxy)" do
      url = URL.build("https://example.com/photo.jpg", width: 200)
      assert url =~ "?w=200"
      assert url =~ "https%3A%2F%2Fexample.com%2Fphoto.jpg"
    end
  end

  describe "round-trip with the server-side parser" do
    test "every URL the client builds parses cleanly on the server" do
      cases = [
        [width: 800],
        [width: 800, height: 600, fit: :cover],
        [width: 400, format: :webp, quality: 80],
        [width: 200, gravity: :face, fit: :cover],
        [brightness: 1.2, contrast: 1.1, saturation: 0.8]
      ]

      for opts <- cases do
        url = URL.build("/photo.jpg", opts)
        # url is "/photo.jpg?<query>"; extract the query and feed to the server parser.
        [_path, query] = String.split(url, "?", parts: 2)

        assert {:ok, %Image.Plug.Pipeline{}} =
                 Image.Plug.Provider.Imgix.Options.parse(query),
               "client-built URL #{inspect(url)} did not parse on the server"
      end
    end

    test "signed URL: client signs, server verifies" do
      url = URL.build("/photo.jpg", width: 200, format: :jpeg, signing_keys: ["test-key"])
      [_path, query] = String.split(url, "?", parts: 2)

      assert :ok =
               Image.Plug.Provider.Imgix.Signing.verify(
                 "/photo.jpg?#{query}",
                 ["test-key"],
                 required?: true
               )
    end
  end
end
