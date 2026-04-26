defmodule Image.Component.CDN.CloudinaryTest do
  use ExUnit.Case, async: true
  doctest Image.Component.CDN.Cloudinary.URL

  alias Image.Component.CDN
  alias Image.Component.CDN.Cloudinary.URL

  describe "atom shorthand" do
    test ":cloudinary resolves to the Cloudinary adapter" do
      assert {Image.Component.CDN.Cloudinary, []} = CDN.resolve(:cloudinary)
    end
  end

  describe "URL.build/2" do
    test "no options yields just the source path under the canonical prefix" do
      assert URL.build("/sample.jpg", account: "demo") ==
               "/demo/image/upload/sample.jpg"
    end

    test "single option yields ?key=value" do
      assert URL.build("/sample.jpg", account: "demo", width: 800) ==
               "/demo/image/upload/w_800/sample.jpg"
    end

    test "options sorted alphabetically (cache-friendly)" do
      assert URL.build("/p.jpg", account: "demo", width: 800, fit: :cover, format: :webp) ==
               "/demo/image/upload/c_fill,f_webp,w_800/p.jpg"
    end

    test "host produces an https origin" do
      assert URL.build("/p.jpg",
               host: "res.cloudinary.com",
               account: "demo",
               width: 200
             ) == "https://res.cloudinary.com/demo/image/upload/w_200/p.jpg"
    end

    test "fit translates to cloudinary vocabulary" do
      assert URL.build("/p.jpg", account: "demo", fit: :contain) ==
               "/demo/image/upload/c_fit/p.jpg"

      assert URL.build("/p.jpg", account: "demo", fit: :cover) ==
               "/demo/image/upload/c_fill/p.jpg"

      assert URL.build("/p.jpg", account: "demo", fit: :pad) ==
               "/demo/image/upload/c_pad/p.jpg"

      assert URL.build("/p.jpg", account: "demo", fit: :scale_down) ==
               "/demo/image/upload/c_limit/p.jpg"

      assert URL.build("/p.jpg", account: "demo", fit: :squeeze) ==
               "/demo/image/upload/c_scale/p.jpg"
    end

    test "format translates to cloudinary vocabulary" do
      assert URL.build("/p.jpg", account: "demo", format: :jpeg) ==
               "/demo/image/upload/f_jpg/p.jpg"

      assert URL.build("/p.jpg", account: "demo", format: :auto) ==
               "/demo/image/upload/f_auto/p.jpg"

      assert URL.build("/p.jpg", account: "demo", format: :webp) ==
               "/demo/image/upload/f_webp/p.jpg"
    end

    test "gravity translates to cloudinary g_ vocabulary" do
      assert URL.build("/p.jpg", account: "demo", gravity: :north) ==
               "/demo/image/upload/g_north/p.jpg"

      assert URL.build("/p.jpg", account: "demo", gravity: :face) ==
               "/demo/image/upload/g_face/p.jpg"

      assert URL.build("/p.jpg", account: "demo", gravity: :north_west) ==
               "/demo/image/upload/g_north_west/p.jpg"
    end

    test "{:xy, x, y} gravity emits g_xy_center,x_<x>,y_<y>" do
      assert URL.build("/p.jpg", account: "demo", gravity: {:xy, 0.25, 0.75}) ==
               "/demo/image/upload/g_xy_center,x_0.25,y_0.75/p.jpg"
    end

    test "background uses rgb: form" do
      assert URL.build("/p.jpg", account: "demo", background: "#ff0000") ==
               "/demo/image/upload/b_rgb:ff0000/p.jpg"

      assert URL.build("/p.jpg", account: "demo", background: "ff0000") ==
               "/demo/image/upload/b_rgb:ff0000/p.jpg"
    end

    test "blur scales by 100" do
      assert URL.build("/p.jpg", account: "demo", blur: 5.0) ==
               "/demo/image/upload/e_blur:500/p.jpg"
    end

    test "sharpen scales by 10" do
      assert URL.build("/p.jpg", account: "demo", sharpen: 5.0) ==
               "/demo/image/upload/e_sharpen:50/p.jpg"
    end

    test "adjust multipliers map to -100..100" do
      assert URL.build("/p.jpg", account: "demo", brightness: 1.2) ==
               "/demo/image/upload/e_brightness:20/p.jpg"

      assert URL.build("/p.jpg", account: "demo", saturation: 0.5) ==
               "/demo/image/upload/e_saturation:-50/p.jpg"
    end

    test "absolute https source defaults to delivery=fetch" do
      url = URL.build("https://example.com/photo.jpg", account: "demo", width: 200)
      assert url == "/demo/image/fetch/w_200/https://example.com/photo.jpg"
    end

    test "explicit :delivery override" do
      assert URL.build("/p.jpg", account: "demo", delivery: "private", width: 100) ==
               "/demo/image/private/w_100/p.jpg"
    end

    test "resource_type override" do
      assert URL.build("/p.jpg", account: "demo", resource_type: "video", width: 100) ==
               "/demo/video/upload/w_100/p.jpg"
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
        url = URL.build("/photo.jpg", [account: "demo"] ++ opts)
        # url is "/demo/image/upload/<transforms>/photo.jpg"; extract
        # the transforms segment and feed it to the server parser.
        transforms = extract_transforms(url)

        assert {:ok, %Image.Plug.Pipeline{}} =
                 Image.Plug.Provider.Cloudinary.Options.parse(transforms),
               "client-built URL #{inspect(url)} did not parse on the server"
      end
    end

    test "signed URL: client signs, server verifies" do
      url =
        URL.build("/photo.jpg",
          account: "demo",
          width: 200,
          format: :jpeg,
          signing_keys: ["test-key"]
        )

      assert :ok =
               Image.Plug.Provider.Cloudinary.Signing.verify(
                 url,
                 ["test-key"],
                 required?: true
               )
    end
  end

  # /demo/image/upload/[s--<sig>--/]<transforms>/<source...>
  defp extract_transforms(url) do
    parts = String.split(url, "/", trim: true)

    case parts do
      [_account, _resource, _delivery, transforms | rest] when rest != [] ->
        # Could be the signature segment; skip it.
        if Regex.match?(~r/^s--/, transforms) do
          [next | _rest] = rest
          next
        else
          transforms
        end

      _ ->
        ""
    end
  end
end
