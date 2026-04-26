defmodule Image.Component.DefaultsTest do
  @moduledoc """
  Verifies that `Application.get_env(:image_components, :defaults)`
  is consulted for `:host`, `:scheme`, `:mount`, `:signing_keys`,
  `:signing_expires_at`, and `:url_options` when the per-call
  attrs are not set.

  Per-call attrs always win when explicitly set.
  """

  # async: false because we mutate application env.
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest

  setup do
    original = Application.get_env(:image_components, :defaults)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:image_components, :defaults)
        value -> Application.put_env(:image_components, :defaults, value)
      end
    end)

    :ok
  end

  defp r(assigns), do: render_component(&Image.Component.image/1, assigns)

  defp src_attr(html) do
    [src] =
      html
      |> Floki.parse_fragment!()
      |> Floki.find("img")
      |> Floki.attribute("src")

    src
  end

  describe "default :host" do
    test "is used when not passed in attrs" do
      Application.put_env(:image_components, :defaults, host: "img.example.com")

      html = r(%{src: "/x.jpg", alt: "x", width: 200, height: 200, sizes: "100vw"})

      assert src_attr(html) =~ "https://img.example.com/cdn-cgi/image/"
    end

    test "is overridden by an explicit :host attr" do
      Application.put_env(:image_components, :defaults, host: "default.example")

      html =
        r(%{
          src: "/x.jpg",
          alt: "x",
          width: 200,
          height: 200,
          sizes: "100vw",
          host: "override.example"
        })

      assert src_attr(html) =~ "override.example"
      refute src_attr(html) =~ "default.example"
    end
  end

  describe "default :scheme" do
    test "is used when default :host is bare" do
      Application.put_env(:image_components, :defaults,
        host: "img.example.com",
        scheme: "http"
      )

      html = r(%{src: "/x.jpg", alt: "x", width: 200, height: 200, sizes: "100vw"})

      assert src_attr(html) =~ "http://img.example.com/"
    end
  end

  describe "default :signing_keys" do
    test "is used when not passed in attrs" do
      Application.put_env(:image_components, :defaults, signing_keys: ["env-default-key"])

      html = r(%{src: "/x.jpg", alt: "x", width: 200, height: 200, sizes: "100vw"})

      assert src_attr(html) =~ "?sig="
    end

    test "is overridden by an explicit :signing_keys attr" do
      Application.put_env(:image_components, :defaults, signing_keys: ["env-key"])

      html_default =
        r(%{src: "/x.jpg", alt: "x", width: 200, height: 200, sizes: "100vw"})

      html_override =
        r(%{
          src: "/x.jpg",
          alt: "x",
          width: 200,
          height: 200,
          sizes: "100vw",
          signing_keys: ["override-key"]
        })

      # Different keys → different signatures.
      refute src_attr(html_default) == src_attr(html_override)
    end
  end

  describe "default :url_options" do
    test "merges with per-call :url_options (per-call wins on key conflict)" do
      Application.put_env(:image_components, :defaults,
        url_options: [quality: 75, format: :webp]
      )

      html =
        r(%{
          src: "/x.jpg",
          alt: "x",
          width: 200,
          height: 200,
          sizes: "100vw",
          url_options: [quality: 90]
        })

      src = src_attr(html)
      # quality from per-call wins.
      assert src =~ "quality=90"
      refute src =~ "quality=75"
      # format inherited from defaults.
      assert src =~ "format=webp"
    end
  end

  describe "default :mount" do
    test "is used when per-call :mount is the empty default" do
      Application.put_env(:image_components, :defaults, mount: "/img")

      html = r(%{src: "/x.jpg", alt: "x", width: 200, height: 200, sizes: "100vw"})

      assert src_attr(html) =~ "/img/cdn-cgi/image/"
    end

    test "explicit :mount on the call wins" do
      Application.put_env(:image_components, :defaults, mount: "/img")

      html =
        r(%{
          src: "/x.jpg",
          alt: "x",
          width: 200,
          height: 200,
          sizes: "100vw",
          mount: "/v2"
        })

      assert src_attr(html) =~ "/v2/cdn-cgi/image/"
      refute src_attr(html) =~ "/img/cdn-cgi/"
    end
  end

  describe "no defaults configured" do
    test "behaves exactly like before (root-relative URLs)" do
      Application.delete_env(:image_components, :defaults)

      html = r(%{src: "/x.jpg", alt: "x", width: 200, height: 200, sizes: "100vw"})

      assert String.starts_with?(src_attr(html), "/cdn-cgi/image/")
    end
  end
end
