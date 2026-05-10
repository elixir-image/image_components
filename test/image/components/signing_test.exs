defmodule Image.Components.SigningTest do
  use ExUnit.Case, async: true

  alias Image.Components.Signing

  doctest Signing

  describe "sign/3" do
    test "appends ?sig=<hex> when path has no query" do
      assert "/x.jpg?sig=" <> rest = Signing.sign("/x.jpg", ["secret"])
      assert String.length(rest) == 64
      assert rest =~ ~r/^[0-9a-f]+$/
    end

    test "appends &sig=<hex> when path already has a query" do
      url = Signing.sign("/x.jpg?w=200", ["secret"])
      assert url =~ ~r/\?w=200&sig=[0-9a-f]{64}$/
    end

    test "uses the first key when multiple are supplied" do
      a = Signing.sign("/x.jpg", ["primary", "rotated_out"])
      b = Signing.sign("/x.jpg", ["primary"])
      assert a == b
    end

    test "different keys produce different signatures" do
      a = Signing.sign("/x.jpg", ["secret_a"])
      b = Signing.sign("/x.jpg", ["secret_b"])
      refute a == b
    end

    test "different paths produce different signatures (same key)" do
      a = Signing.sign("/a.jpg", ["secret"])
      b = Signing.sign("/b.jpg", ["secret"])
      refute a == b
    end

    test "expires_at as DateTime appends exp=<unix> before sig" do
      dt = ~U[2026-12-31 23:59:59Z]
      url = Signing.sign("/x.jpg", ["secret"], expires_at: dt)
      assert url =~ ~r/\?exp=#{DateTime.to_unix(dt)}&sig=[0-9a-f]{64}$/
    end

    test "expires_at as integer appends as-is" do
      url = Signing.sign("/x.jpg", ["secret"], expires_at: 1_800_000_000)
      assert url =~ ~r/\?exp=1800000000&sig=[0-9a-f]{64}$/
    end

    test "different expires_at values produce different sigs" do
      a = Signing.sign("/x.jpg", ["secret"], expires_at: 1)
      b = Signing.sign("/x.jpg", ["secret"], expires_at: 2)
      refute a == b
    end

    test "wire-format compatible with Image.Plug.Signing" do
      # Same algorithm, same parameter names, same encoding —
      # so a signature emitted here verifies on the back-end.
      path = "/cdn-cgi/image/width=200/photo.jpg"
      url = Signing.sign(path, ["test_key"])
      <<_::binary-size(byte_size(path)), "?sig=", hex::binary-size(64)>> = url
      # Recompute manually and compare.
      expected = :crypto.mac(:hmac, :sha256, "test_key", path) |> Base.encode16(case: :lower)
      assert hex == expected
    end
  end
end
