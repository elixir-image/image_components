defmodule Image.Component.SigningTest do
  use ExUnit.Case, async: true
  doctest Image.Component.Signing

  alias Image.Component.{Signing, URL}

  describe "Signing.sign/3" do
    test "matches the back-end Image.Plug.Signing output for the same path + key" do
      # Sanity: the wire format is shared. If anyone changes the
      # canonical-string rule on either side without the other,
      # this test fails.
      path = "/cdn-cgi/image/width=200/photo.jpg"
      keys = ["secret"]

      ours = Signing.sign(path, keys)
      theirs = Image.Plug.Signing.sign(path, keys)

      assert ours == theirs
    end

    test "DateTime expiry round-trips" do
      expiry = DateTime.from_unix!(2_000_000_000)
      signed = Signing.sign("/foo.jpg", ["secret"], expires_at: expiry)
      assert signed =~ "?exp=2000000000"
    end
  end

  describe "URL.build/2 with :signing_keys" do
    test "appends ?sig= when :signing_keys is set" do
      built = URL.build("/photo.jpg", width: 200, signing_keys: ["secret"])
      assert built =~ "?sig="
    end

    test "back-end can verify a URL the component generated" do
      built = URL.build("/photo.jpg", width: 200, signing_keys: ["secret"])
      assert :ok = Image.Plug.Signing.verify(built, ["secret"], required?: true)
    end

    test "expiry threads through both paths" do
      future = System.system_time(:second) + 3600
      built = URL.build("/photo.jpg", width: 200, signing_keys: ["secret"], signing_expires_at: future)

      assert built =~ "?exp=#{future}"
      assert built =~ "&sig="
      assert :ok = Image.Plug.Signing.verify(built, ["secret"], required?: true)
    end

    test "no signing when :signing_keys is omitted (default)" do
      built = URL.build("/photo.jpg", width: 200)
      refute built =~ "?sig="
    end
  end
end
