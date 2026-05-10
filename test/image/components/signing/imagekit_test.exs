defmodule Image.Components.Signing.ImageKitTest do
  use ExUnit.Case, async: true

  alias Image.Components.Signing.ImageKit

  doctest ImageKit

  describe "sign/3" do
    test "appends ?ik-s=<hex> when path has no query" do
      url = ImageKit.sign("/demo/tr:w-200/cat.jpg", ["k"])
      assert url =~ ~r/^\/demo\/tr:w-200\/cat\.jpg\?ik-s=[0-9a-f]{40}$/
    end

    test "appends &ik-s=<hex> when path has a query" do
      url = ImageKit.sign("/demo/cat.jpg?tr=w-200", ["k"])
      assert url =~ ~r/^\/demo\/cat\.jpg\?tr=w-200&ik-s=[0-9a-f]{40}$/
    end

    test "expires_at as DateTime appends ik-t=<unix>" do
      dt = ~U[2026-12-31 23:59:59Z]
      url = ImageKit.sign("/demo/cat.jpg", ["k"], expires_at: dt)
      assert url =~ ~r/\?ik-t=#{DateTime.to_unix(dt)}&ik-s=[0-9a-f]{40}$/
    end

    test "different keys produce different signatures" do
      refute ImageKit.sign("/x.jpg", ["k1"]) == ImageKit.sign("/x.jpg", ["k2"])
    end

    test "wire format: HMAC-SHA1 over the path-and-query (after ik-t added)" do
      url = ImageKit.sign("/demo/cat.jpg", ["secret"])
      [sig] = Regex.run(~r/\?ik-s=([0-9a-f]+)$/, url, capture: :all_but_first)
      expected =
        :crypto.mac(:hmac, :sha, "secret", "/demo/cat.jpg")
        |> Base.encode16(case: :lower)
      assert sig == expected
    end

    test "SHA-1 signature length is 40 hex chars" do
      url = ImageKit.sign("/x.jpg", ["k"])
      [sig] = Regex.run(~r/\?ik-s=([0-9a-f]+)$/, url, capture: :all_but_first)
      assert String.length(sig) == 40
    end
  end
end
