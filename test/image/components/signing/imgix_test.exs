defmodule Image.Components.Signing.ImgixTest do
  use ExUnit.Case, async: true

  alias Image.Components.Signing.Imgix

  doctest Imgix

  describe "sign/3" do
    test "appends ?s=<hex> when path has no query" do
      url = Imgix.sign("/cat.jpg", ["secret"])
      assert url =~ ~r/^\/cat\.jpg\?s=[0-9a-f]{64}$/
    end

    test "appends &s=<hex> when path has a query" do
      url = Imgix.sign("/cat.jpg?w=200", ["secret"])
      assert url =~ ~r/^\/cat\.jpg\?w=200&s=[0-9a-f]{64}$/
    end

    test "different keys produce different signatures" do
      refute Imgix.sign("/cat.jpg", ["k1"]) == Imgix.sign("/cat.jpg", ["k2"])
    end

    test "expires_at as DateTime appends expires=<unix>" do
      dt = ~U[2026-12-31 23:59:59Z]
      url = Imgix.sign("/cat.jpg", ["k"], expires_at: dt)
      assert url =~ ~r/\?expires=#{DateTime.to_unix(dt)}&s=[0-9a-f]{64}$/
    end

    test "expires_at as integer appends as-is" do
      url = Imgix.sign("/cat.jpg", ["k"], expires_at: 1_800_000_000)
      assert url =~ ~r/\?expires=1800000000&s=[0-9a-f]{64}$/
    end

    test "different expires values produce different signatures" do
      refute Imgix.sign("/x.jpg", ["k"], expires_at: 1) ==
               Imgix.sign("/x.jpg", ["k"], expires_at: 2)
    end

    test "wire format: HMAC-SHA256 over (key <> path)" do
      url = Imgix.sign("/cat.jpg?w=200", ["secret"])
      [sig] = Regex.run(~r/&s=([0-9a-f]+)$/, url, capture: :all_but_first)
      expected =
        :crypto.mac(:hmac, :sha256, "secret", "secret/cat.jpg?w=200")
        |> Base.encode16(case: :lower)
      assert sig == expected
    end
  end
end
