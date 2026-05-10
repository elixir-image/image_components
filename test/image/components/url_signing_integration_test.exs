defmodule Image.Components.URLSigningIntegrationTest do
  @moduledoc """
  Integration tests for the `:sign` option threaded through every
  `Image.Components.URL.<provider>/2` builder. Confirms that:

    * passing `sign: [keys]` produces a URL whose signature segment
      matches what the matching `Image.Components.Signing.<vendor>`
      module would produce on its own;
    * not passing `:sign` leaves the URL untouched (no signature
      segment appears);
    * `:sign_expires_at` is plumbed through.
  """

  use ExUnit.Case, async: true

  alias Image.Components.URL
  alias Image.Plug.Pipeline
  alias Image.Plug.Pipeline.Ops

  @pipeline %Pipeline{
    ops: [%Ops.Resize{width: 200, upscale?: false}],
    output: nil
  }

  describe "no :sign option" do
    test "Cloudflare URL has no ?sig=" do
      url = URL.cloudflare(@pipeline, source_path: "/cat.jpg")
      refute url =~ "sig="
    end

    test "Cloudinary URL has no /s--…--/" do
      url = URL.cloudinary(@pipeline, source_path: "/cat.jpg")
      refute url =~ "/s--"
    end

    test "imgix URL has no &s=" do
      url = URL.imgix(@pipeline, source_path: "/cat.jpg")
      refute url =~ "s="
    end

    test "ImageKit URL has no ik-s=" do
      url = URL.imagekit(@pipeline, source_path: "/cat.jpg")
      refute url =~ "ik-s="
    end
  end

  describe ":sign with keys" do
    test "Cloudflare appends ?sig=<hex>" do
      url = URL.cloudflare(@pipeline, source_path: "/cat.jpg", sign: ["secret"])
      assert url =~ ~r/\?sig=[0-9a-f]{64}$/
    end

    test "Cloudinary inserts /s--<base64url>--/" do
      url = URL.cloudinary(@pipeline, source_path: "/cat.jpg", sign: ["api_secret"])
      assert url =~ ~r"/s--[A-Za-z0-9_-]{32}--/"
    end

    test "imgix appends &s=<hex>" do
      url = URL.imgix(@pipeline, source_path: "/cat.jpg", sign: ["secret"])
      assert url =~ ~r/[?&]s=[0-9a-f]{64}$/
    end

    test "ImageKit appends ?ik-s=<sha1-hex>" do
      url = URL.imagekit(@pipeline, source_path: "/cat.jpg", sign: ["k"])
      assert url =~ ~r/[?&]ik-s=[0-9a-f]{40}$/
    end

    test "host is preserved across signing (origin not signed)" do
      url =
        URL.cloudflare(@pipeline,
          source_path: "/cat.jpg",
          host: "https://images.example.com",
          sign: ["secret"]
        )

      assert String.starts_with?(url, "https://images.example.com/cdn-cgi/image/")
      assert url =~ ~r/\?sig=[0-9a-f]{64}$/
    end
  end

  describe ":sign_expires_at" do
    test "Cloudflare propagates exp= and re-signs" do
      url =
        URL.cloudflare(@pipeline,
          source_path: "/cat.jpg",
          sign: ["secret"],
          sign_expires_at: 1_900_000_000
        )

      assert url =~ ~r/\?exp=1900000000&sig=[0-9a-f]{64}$/
    end

    test "imgix propagates expires= and re-signs" do
      url =
        URL.imgix(@pipeline,
          source_path: "/cat.jpg",
          sign: ["secret"],
          sign_expires_at: 1_900_000_000
        )

      assert url =~ ~r/[?&]expires=1900000000&s=[0-9a-f]{64}$/
    end

    test "ImageKit propagates ik-t= and re-signs" do
      url =
        URL.imagekit(@pipeline,
          source_path: "/cat.jpg",
          sign: ["k"],
          sign_expires_at: 1_900_000_000
        )

      assert url =~ ~r/[?&]ik-t=1900000000&ik-s=[0-9a-f]{40}$/
    end
  end
end
