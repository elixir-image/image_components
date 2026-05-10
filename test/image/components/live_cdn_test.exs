defmodule Image.Components.LiveCdnTest do
  @moduledoc """
  Live integration tests against the public demo endpoints of three
  of the four supported CDNs:

    * Cloudinary `res.cloudinary.com/demo/...`
    * imgix `assets.imgix.net/...`
    * ImageKit `ik.imagekit.io/demo/...`

  Each test builds a URL via `Image.Components.URL.<provider>/2`
  pointed at the demo host, fetches it, and asserts:

    * HTTP 200 (the demo service accepted our URL)
    * Content-Type is an image MIME (the demo service rendered
      a transformed image, not an HTML error page)
    * The response body decodes via `Image.from_binary/1`
    * The decoded dimensions roughly match what we asked for

  This is the highest-confidence test we can run for those three
  CDNs without a paid account — it's the real edge service
  rendering our URLs.

  **Cloudflare Images is not covered** because Cloudflare doesn't
  publish a public demo account hash. See `cross_sdk_test.exs`
  for cross-validation against the official SDKs (also no
  Cloudflare coverage there for the same reason — Cloudflare
  doesn't ship a first-party URL builder).

  Tagged `:live_cdn`; **excluded by default** because each test
  hits the public Internet. Run with:

      mix test --include live_cdn

  Slow — typically 1–3 s per test, network-dependent.
  """

  use ExUnit.Case, async: true

  alias Image.Components.URL
  alias Image.Plug.Pipeline
  alias Image.Plug.Pipeline.Ops

  @moduletag :live_cdn
  @moduletag timeout: 30_000

  describe "Cloudinary demo (res.cloudinary.com/demo)" do
    @host "https://res.cloudinary.com"
    @source "/sample.jpg"

    test "width=400 cover" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 400, height: 400, fit: :cover}],
        output: %Ops.Format{type: :jpeg, quality: 75}
      }

      url = URL.cloudinary(pipeline, source_path: @source, host: @host, cloudinary_account: "demo")
      {:ok, image, content_type} = fetch_image(url)

      assert content_type =~ ~r{^image/}
      assert_dimensions(image, expected_width: 400, expected_height: 400)
    end

    test "vignette renders" do
      pipeline = %Pipeline{
        ops: [
          %Ops.Resize{width: 600},
          %Ops.Vignette{strength: 0.6}
        ],
        output: %Ops.Format{type: :jpeg, quality: 75}
      }

      url = URL.cloudinary(pipeline, source_path: @source, host: @host, cloudinary_account: "demo")
      {:ok, image, content_type} = fetch_image(url)

      assert content_type =~ ~r{^image/}
      assert_dimensions(image, expected_width: 600)
    end

    test "blur sigma=4 → e_blur:400" do
      pipeline = %Pipeline{
        ops: [
          %Ops.Resize{width: 400},
          %Ops.Blur{sigma: 4.0}
        ],
        output: %Ops.Format{type: :jpeg, quality: 75}
      }

      url = URL.cloudinary(pipeline, source_path: @source, host: @host, cloudinary_account: "demo")
      {:ok, image, content_type} = fetch_image(url)

      assert content_type =~ ~r{^image/}
      assert_dimensions(image, expected_width: 400)
    end
  end

  describe "imgix demo (assets.imgix.net)" do
    @host "https://assets.imgix.net"
    @source "/frog.jpg"

    test "width=400 + format=auto" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 400, height: 400, fit: :cover}],
        output: %Ops.Format{type: :auto, quality: 80}
      }

      url = URL.imgix(pipeline, source_path: @source, host: @host)
      {:ok, image, content_type} = fetch_image(url)

      assert content_type =~ ~r{^image/}
      assert_dimensions(image, expected_width: 400, expected_height: 400)
    end

    test "monochrome tint" do
      pipeline = %Pipeline{
        ops: [
          %Ops.Resize{width: 400},
          %Ops.Tint{color: [128, 80, 200]}
        ],
        output: %Ops.Format{type: :jpeg, quality: 75}
      }

      url = URL.imgix(pipeline, source_path: @source, host: @host)
      {:ok, image, content_type} = fetch_image(url)

      assert content_type =~ ~r{^image/}
      assert_dimensions(image, expected_width: 400)
    end

    test "centred percentage adjust effects" do
      pipeline = %Pipeline{
        ops: [
          %Ops.Resize{width: 400},
          %Ops.Adjust{brightness: 1.2, contrast: 1.3, saturation: 1.0, gamma: 1.0}
        ],
        output: %Ops.Format{type: :jpeg, quality: 75}
      }

      url = URL.imgix(pipeline, source_path: @source, host: @host)
      {:ok, image, content_type} = fetch_image(url)

      assert content_type =~ ~r{^image/}
      assert_dimensions(image, expected_width: 400)
    end
  end

  describe "ImageKit demo (ik.imagekit.io/demo)" do
    @host "https://ik.imagekit.io"
    @source "/medium_cafe_B1iTdD0C.jpg"

    test "width=400 + extract crop" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 400, height: 400, fit: :cover}],
        output: %Ops.Format{type: :jpeg, quality: 75}
      }

      url =
        URL.imagekit(pipeline,
          source_path: @source,
          host: @host,
          imagekit_endpoint: "demo"
        )

      {:ok, image, content_type} = fetch_image(url)

      assert content_type =~ ~r{^image/}
      assert_dimensions(image, expected_width: 400, expected_height: 400)
    end

    test "format=webp + quality=70" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 600}],
        output: %Ops.Format{type: :webp, quality: 70}
      }

      url =
        URL.imagekit(pipeline,
          source_path: @source,
          host: @host,
          imagekit_endpoint: "demo"
        )

      {:ok, image, content_type} = fetch_image(url)

      assert content_type =~ ~r{webp}
      assert_dimensions(image, expected_width: 600)
    end

    test "blur sigma=2 → e-blur-200" do
      pipeline = %Pipeline{
        ops: [
          %Ops.Resize{width: 400},
          %Ops.Blur{sigma: 2.0}
        ],
        output: %Ops.Format{type: :jpeg, quality: 75}
      }

      url =
        URL.imagekit(pipeline,
          source_path: @source,
          host: @host,
          imagekit_endpoint: "demo"
        )

      {:ok, image, content_type} = fetch_image(url)

      assert content_type =~ ~r{^image/}
      assert_dimensions(image, expected_width: 400)
    end
  end

  # ── helpers ─────────────────────────────────────────────────────

  defp fetch_image(url) do
    case Req.get(url, retry: false, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: body, headers: headers}} when is_binary(body) ->
        ct = content_type(headers)

        case Image.from_binary(body) do
          {:ok, image} -> {:ok, image, ct}
          {:error, reason} -> flunk("Image.from_binary failed for #{url}: #{inspect(reason)}")
        end

      {:ok, %{status: status, body: body}} ->
        flunk("""
        Live CDN returned non-200 for #{url}:
          status: #{status}
          body:   #{inspect(String.slice(IO.iodata_to_binary([body]), 0, 200))}
        """)

      {:error, reason} ->
        flunk("Network error fetching #{url}: #{inspect(reason)}")
    end
  end

  defp content_type(headers) do
    headers
    |> Enum.find_value(fn
      {"content-type", v} -> v
      {"Content-Type", v} -> v
      _ -> nil
    end)
    |> case do
      nil -> ""
      [v | _] -> v
      v when is_binary(v) -> v
    end
  end

  defp assert_dimensions(image, expectations) do
    width = Image.width(image)
    height = Image.height(image)

    if expected = Keyword.get(expectations, :expected_width) do
      assert_in_delta width, expected, 2,
        "expected width near #{expected}, got #{width}"
    end

    if expected = Keyword.get(expectations, :expected_height) do
      assert_in_delta height, expected, 2,
        "expected height near #{expected}, got #{height}"
    end
  end
end
