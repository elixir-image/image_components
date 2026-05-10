defmodule Image.Components.Signing.CloudinaryTest do
  use ExUnit.Case, async: true

  alias Image.Components.Signing.Cloudinary

  doctest Cloudinary

  describe "sign/3" do
    test "inserts s--<sig>--/ between delivery and transforms" do
      url = Cloudinary.sign("/demo/image/upload/w_200/cat.jpg", ["api_secret"])
      assert url =~ ~r"^/demo/image/upload/s--[A-Za-z0-9_-]{32}--/w_200/cat\.jpg$"
    end

    test "transforms-and-source are signed (not the prefix)" do
      a = Cloudinary.sign("/demo/image/upload/w_200/cat.jpg", ["k"])
      b = Cloudinary.sign("/other/image/upload/w_200/cat.jpg", ["k"])

      sig_a = Regex.run(~r{s--([^-]+)--}, a) |> Enum.at(1)
      sig_b = Regex.run(~r{s--([^-]+)--}, b) |> Enum.at(1)

      # Same transforms+source → same signature, even though
      # account/prefix differs.
      assert sig_a == sig_b
    end

    test "different keys produce different signatures" do
      a = Cloudinary.sign("/demo/image/upload/w_200/cat.jpg", ["secret_a"])
      b = Cloudinary.sign("/demo/image/upload/w_200/cat.jpg", ["secret_b"])
      refute a == b
    end

    test "uses first key when multiple supplied" do
      a = Cloudinary.sign("/demo/image/upload/w_200/cat.jpg", ["primary", "rotated"])
      b = Cloudinary.sign("/demo/image/upload/w_200/cat.jpg", ["primary"])
      assert a == b
    end

    test "signature is base64url-truncated to 32 chars" do
      url = Cloudinary.sign("/demo/image/upload/w_200/cat.jpg", ["k"])
      [sig] = Regex.run(~r{s--([^-]+)--}, url, capture: :all_but_first)
      assert String.length(sig) == 32
      # base64url charset: A-Z a-z 0-9 _ -
      assert sig =~ ~r/^[A-Za-z0-9_-]+$/
    end
  end
end
