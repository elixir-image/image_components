defmodule Image.Component.CDNTest do
  use ExUnit.Case, async: true
  doctest Image.Component.CDN

  alias Image.Component.CDN

  describe "resolve/1" do
    test "atom :cloudflare maps to Cloudflare adapter" do
      assert {Image.Component.CDN.Cloudflare, []} = CDN.resolve(:cloudflare)
    end

    test "nil maps to default Cloudflare adapter" do
      assert {Image.Component.CDN.Cloudflare, []} = CDN.resolve(nil)
    end

    test "{module, opts} passes through" do
      assert {Image.Component.CDN.Cloudflare, [foo: 1]} =
               CDN.resolve({Image.Component.CDN.Cloudflare, [foo: 1]})
    end

    test "raises on unknown atom" do
      assert_raise ArgumentError, ~r/unknown CDN adapter/, fn ->
        CDN.resolve(:not_a_real_cdn)
      end
    end
  end

  describe "Cloudflare adapter delegates to URL + Signing" do
    alias Image.Component.CDN.Cloudflare

    test "build_url matches Image.Component.URL.build" do
      a = Cloudflare.build_url("/x.jpg", width: 200, format: :webp)
      b = Image.Component.URL.build("/x.jpg", width: 200, format: :webp)
      assert a == b
    end

    test "sign_url matches Image.Component.Signing.sign" do
      a = Cloudflare.sign_url("/x.jpg", ["secret"], [])
      b = Image.Component.Signing.sign("/x.jpg", ["secret"])
      assert a == b
    end
  end

  describe "<.image cdn={...}>" do
    import Phoenix.LiveViewTest

    defmodule UppercaseCDN do
      @behaviour Image.Component.CDN

      @impl true
      def build_url(source, options) do
        # Trivial test adapter: encode width as `?W=N` instead of
        # the Cloudflare options-segment grammar. Distinct enough
        # that the test can confirm the dispatch reaches us.
        width = Keyword.get(options, :width, "x")
        "TEST://#{source}?W=#{width}"
      end

      @impl true
      def sign_url(url, _keys, _options), do: url <> "&signed"
    end

    test "an explicit :cdn attr overrides the default" do
      html =
        render_component(&Image.Component.image/1, %{
          src: "/photo.jpg",
          alt: "x",
          width: 200,
          height: 200,
          sizes: "100vw",
          cdn: UppercaseCDN
        })

      [src] =
        html
        |> Floki.parse_fragment!()
        |> Floki.find("img")
        |> Floki.attribute("src")

      assert String.starts_with?(src, "TEST:///photo.jpg")
    end
  end

  describe "Application env :cdn default" do
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

    test ":cdn is read from Application defaults when no per-call attr" do
      Application.put_env(:image_components, :defaults, cdn: :cloudflare)

      html =
        render_component(&Image.Component.image/1, %{
          src: "/x.jpg",
          alt: "x",
          width: 200,
          height: 200,
          sizes: "100vw"
        })

      assert html =~ "/cdn-cgi/image/"
    end
  end
end
