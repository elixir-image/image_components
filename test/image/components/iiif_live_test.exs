defmodule Image.Components.IIIFLiveTest do
  @moduledoc """
  Live integration tests against public IIIF Image API servers.
  Builds URLs via `Image.Components.URL.iiif/2`, fetches them,
  and asserts the response decodes to an image of the requested
  dimensions.

  Two endpoints are exercised:

    * **IIIF Cookbook reference image** at `iiif.io` — the canonical
      Image API 3.0 fixture maintained by the IIIF Consortium.

    * **Wellcome Collection** at `iiif.wellcomecollection.org` —
      a real production IIIF deployment (Loris-backed); accepts
      the 3.0-compatible subset of syntax our projector emits.

  Tagged `:live_iiif`; **excluded by default** because tests hit
  the public Internet. Run with:

      mix test --include live_iiif

  ~2-5 s per test, network-dependent.
  """

  use ExUnit.Case, async: true

  alias Image.Components.URL
  alias Image.Plug.Pipeline
  alias Image.Plug.Pipeline.Ops

  @moduletag :live_iiif
  @moduletag timeout: 30_000

  describe "IIIF Cookbook reference image (iiif.io, Image API 3.0)" do
    @host "https://iiif.io"
    @prefix "/api/image/3.0/example/reference"
    @identifier "/918ecd18c2592080851777620de9bcb5-gottingen"

    test "max size, no transform — full original" do
      pipeline = %Pipeline{ops: [], output: nil}

      url =
        URL.iiif(pipeline,
          source_path: @identifier,
          host: @host,
          iiif_prefix: @prefix
        )

      assert {:ok, image, content_type} = fetch_image(url)
      assert content_type =~ ~r{^image/}
      # The reference image is 4032×3024 — just assert non-trivial
      # dimensions; the size segment is `max` so we get the original.
      assert Image.width(image) > 100
      assert Image.height(image) > 100
    end

    test "width=400 — proportional resize" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 400, upscale?: false}],
        output: nil
      }

      url =
        URL.iiif(pipeline,
          source_path: @identifier,
          host: @host,
          iiif_prefix: @prefix
        )

      assert {:ok, image, content_type} = fetch_image(url)
      assert content_type =~ ~r{^image/}
      assert Image.width(image) == 400
    end

    test "rotation=90" do
      pipeline = %Pipeline{
        ops: [
          %Ops.Resize{width: 400, upscale?: false},
          %Ops.Rotate{angle: 90}
        ],
        output: nil
      }

      url =
        URL.iiif(pipeline,
          source_path: @identifier,
          host: @host,
          iiif_prefix: @prefix
        )

      assert {:ok, image, _content_type} = fetch_image(url)
      # IIIF processes size BEFORE rotation. The source is 4:3
      # (4032×3024); resize to width=400 → 400×300; rotate 90° →
      # 300×400. So the post-rotation width is the original
      # height-after-resize.
      assert Image.height(image) == 400
    end

    test "quality=gray — saturation: 0.0 in IR projects to /gray" do
      pipeline = %Pipeline{
        ops: [
          %Ops.Resize{width: 200, upscale?: false},
          %Ops.Adjust{saturation: 0.0}
        ],
        output: nil
      }

      url =
        URL.iiif(pipeline,
          source_path: @identifier,
          host: @host,
          iiif_prefix: @prefix
        )

      assert url =~ "/gray.jpg"
      assert {:ok, image, _content_type} = fetch_image(url)
      assert Image.width(image) == 200
    end

    test "format=png" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 200, upscale?: false}],
        output: %Ops.Format{type: :png, quality: 80}
      }

      url =
        URL.iiif(pipeline,
          source_path: @identifier,
          host: @host,
          iiif_prefix: @prefix
        )

      assert url =~ "default.png"
      assert {:ok, _image, content_type} = fetch_image(url)
      assert content_type =~ ~r{png}
    end
  end

  describe "Wellcome Collection (production IIIF)" do
    @host "https://iiif.wellcomecollection.org"
    @prefix "/image"
    @identifier "/V0007727.jpg"

    test "width=200" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 200, upscale?: false}],
        output: nil
      }

      url =
        URL.iiif(pipeline,
          source_path: @identifier,
          host: @host,
          iiif_prefix: @prefix
        )

      assert {:ok, image, content_type} = fetch_image(url)
      assert content_type =~ ~r{^image/}
      assert Image.width(image) == 200
    end

    test "rotation=180" do
      pipeline = %Pipeline{
        ops: [
          %Ops.Resize{width: 200, upscale?: false},
          %Ops.Rotate{angle: 180}
        ],
        output: nil
      }

      url =
        URL.iiif(pipeline,
          source_path: @identifier,
          host: @host,
          iiif_prefix: @prefix
        )

      assert {:ok, image, _content_type} = fetch_image(url)
      assert Image.width(image) == 200
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
        Live IIIF returned non-200 for #{url}:
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
end
