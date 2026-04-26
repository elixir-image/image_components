defmodule Image.Component.URLTest do
  use ExUnit.Case, async: true
  doctest Image.Component.URL

  alias Image.Component.URL

  describe "build/2" do
    test "no options yields the source path through the (empty) mount" do
      assert URL.build("/foo.jpg") == "/foo.jpg"
    end

    test "single option yields a /cdn-cgi/image/ URL" do
      assert URL.build("/foo.jpg", width: 200) == "/cdn-cgi/image/width=200/foo.jpg"
    end

    test "multiple options are sorted alphabetically (cache-friendly)" do
      assert URL.build("/foo.jpg", width: 200, fit: :cover, format: :webp) ==
               "/cdn-cgi/image/fit=cover,format=webp,width=200/foo.jpg"
    end

    test "two callers with the same options in different order produce identical URLs" do
      a = URL.build("/foo.jpg", width: 200, format: :webp)
      b = URL.build("/foo.jpg", format: :webp, width: 200)
      assert a == b
    end

    test "absolute https URLs survive in the source segment" do
      assert URL.build("https://x.example/y.jpg", width: 100) ==
               "/cdn-cgi/image/width=100/https://x.example/y.jpg"
    end

    test "mount prefixes the URL" do
      assert URL.build("/foo.jpg", mount: "/img", width: 100) ==
               "/img/cdn-cgi/image/width=100/foo.jpg"
    end

    test "host with bare hostname uses default https scheme" do
      assert URL.build("/foo.jpg", host: "img.example.com", width: 100) ==
               "https://img.example.com/cdn-cgi/image/width=100/foo.jpg"
    end

    test "host with explicit scheme is honoured" do
      assert URL.build("/foo.jpg", host: "img.example.com", scheme: "http", width: 100) ==
               "http://img.example.com/cdn-cgi/image/width=100/foo.jpg"
    end

    test "host with explicit scheme prefix is preserved" do
      assert URL.build("/foo.jpg", host: "https://img.example.com", width: 100) ==
               "https://img.example.com/cdn-cgi/image/width=100/foo.jpg"
    end

    test "host + mount combine" do
      assert URL.build("/foo.jpg", host: "img.example.com", mount: "/v1", width: 100) ==
               "https://img.example.com/v1/cdn-cgi/image/width=100/foo.jpg"
    end

    test "fit values produce hyphenated forms when needed" do
      assert URL.build("/x.jpg", fit: :scale_down) == "/cdn-cgi/image/fit=scale-down/x.jpg"
    end

    test "format=baseline_jpeg becomes baseline-jpeg" do
      assert URL.build("/x.jpg", format: :baseline_jpeg) ==
               "/cdn-cgi/image/format=baseline-jpeg/x.jpg"
    end

    test "compass gravities collapse to Cloudflare's spelling" do
      assert URL.build("/x.jpg", gravity: :north_east) ==
               "/cdn-cgi/image/gravity=northeast/x.jpg"
    end

    test "width=:auto is preserved as the literal `auto`" do
      assert URL.build("/x.jpg", width: :auto) == "/cdn-cgi/image/width=auto/x.jpg"
    end
  end
end
