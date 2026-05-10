defmodule Image.Components.CrossSdkTest do
  @moduledoc """
  Cross-validates `Image.Components.URL.<provider>/2` output against
  the official vendor URL-builder SDKs (Cloudinary, imgix, ImageKit).

  For each canonical "intent" — a small library of representative
  transforms — we build the URL two ways:

    * via `Image.Components.URL.<provider>/2`, the projector under test
    * via the vendor's official Node SDK, shelled out to the helper at
      `test/support/cross_sdk/bin/build-url.js`

  We then compare the two URLs in **normalised form** — sorted
  comma-tokens for the path-prefix providers (Cloudinary, ImageKit),
  sorted query params for imgix. Order differences and SDK-tracking
  parameters (`?_a=…` for Cloudinary, `ixlib=js-…` for imgix) are
  filtered out by both sides; what remains is the operation set.

  Cloudflare Images has no first-party URL-builder SDK, so it is not
  cross-validated here. See `live_cdn_test.exs` for the
  demo-endpoint live integration tests, which cover Cloudinary,
  imgix, and ImageKit only for the same reason.

  Tagged `:cross_sdk`; **excluded by default** because it requires
  Node + an `npm install` in `test/support/cross_sdk/`. Run with:

      cd test/support/cross_sdk && npm install
      mix test --include cross_sdk

  """

  use ExUnit.Case, async: true

  alias Image.Components.URL
  alias Image.Plug.Pipeline
  alias Image.Plug.Pipeline.Ops

  @moduletag :cross_sdk
  @moduletag timeout: 30_000

  @sdk_dir Path.expand("../../support/cross_sdk", __DIR__)

  setup_all do
    unless File.exists?(Path.join(@sdk_dir, "node_modules")) do
      flunk(
        "Cross-SDK harness not installed. Run:\n" <>
          "    cd #{@sdk_dir} && npm install"
      )
    end

    :ok
  end

  describe "Cloudinary parity" do
    test "width + height + cover crop" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 600, height: 400, fit: :cover}],
        output: nil
      }

      ours = URL.cloudinary(pipeline, source_path: "/cat.jpg", host: "https://res.cloudinary.com")

      theirs =
        sdk_url("cloudinary", "/cat.jpg", %{
          "cloud_name" => "demo",
          "options" => %{
            "transformation" => [%{"width" => 600, "height" => 400, "crop" => "fill"}]
          }
        })

      assert_path_token_set_equal(ours, theirs)
    end

    test "width + format + quality" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 800}],
        output: %Ops.Format{type: :webp, quality: 80}
      }

      ours = URL.cloudinary(pipeline, source_path: "/cat.jpg", host: "https://res.cloudinary.com")

      theirs =
        sdk_url("cloudinary", "/cat.jpg", %{
          "cloud_name" => "demo",
          "options" => %{
            "transformation" => [
              %{"width" => 800, "fetch_format" => "webp", "quality" => 80}
            ]
          }
        })

      assert_path_token_set_equal(ours, theirs)
    end

    test "face-aware crop with z (face_zoom)" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 400, fit: :cover, gravity: :face, face_zoom: 0.6}],
        output: nil
      }

      ours = URL.cloudinary(pipeline, source_path: "/portrait.jpg", host: "https://res.cloudinary.com")

      theirs =
        sdk_url("cloudinary", "/portrait.jpg", %{
          "cloud_name" => "demo",
          "options" => %{
            "transformation" => [
              %{"width" => 400, "crop" => "fill", "gravity" => "face", "zoom" => 0.6}
            ]
          }
        })

      assert_path_token_set_equal(ours, theirs)
    end
  end

  describe "imgix parity" do
    test "width + cover" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 600, fit: :cover}],
        output: nil
      }

      ours = URL.imgix(pipeline, source_path: "/cat.jpg", host: "https://assets.imgix.net")
      theirs = sdk_url("imgix", "/cat.jpg", %{"options" => %{"w" => 600, "fit" => "crop"}})

      assert_query_set_equal(ours, theirs)
    end

    test "width + format=webp + quality" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 800}],
        output: %Ops.Format{type: :webp, quality: 80}
      }

      ours = URL.imgix(pipeline, source_path: "/cat.jpg", host: "https://assets.imgix.net")

      theirs =
        sdk_url("imgix", "/cat.jpg", %{"options" => %{"w" => 800, "fm" => "webp", "q" => 80}})

      assert_query_set_equal(ours, theirs)
    end

    test "face-aware crop" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 400, height: 400, fit: :cover, gravity: :face}],
        output: nil
      }

      ours = URL.imgix(pipeline, source_path: "/portrait.jpg", host: "https://assets.imgix.net")

      theirs =
        sdk_url("imgix", "/portrait.jpg", %{
          "options" => %{"w" => 400, "h" => 400, "fit" => "crop", "crop" => "faces"}
        })

      assert_query_set_equal(ours, theirs)
    end
  end

  describe "ImageKit parity" do
    test "width + force" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 600, fit: :squeeze}],
        output: nil
      }

      ours =
        URL.imagekit(pipeline,
          source_path: "/cat.jpg",
          host: "https://ik.imagekit.io",
          imagekit_endpoint: "demo"
        )

      theirs =
        sdk_url("imagekit", "/cat.jpg", %{
          "transformation" => [%{"width" => "600", "crop" => "force"}]
        })

      assert_path_token_set_equal(ours, theirs)
    end

    test "width + height + extract + format=webp + non-default quality" do
      # Use quality=75 (not the ImageKit default of 80) so both
      # sides emit `q-75`. Our projector drops `q` when it equals
      # the default; the SDK always emits it. See
      # `test "default-trim divergence is intentional"` below.
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 600, height: 400, fit: :cover}],
        output: %Ops.Format{type: :webp, quality: 75}
      }

      ours =
        URL.imagekit(pipeline,
          source_path: "/cat.jpg",
          host: "https://ik.imagekit.io",
          imagekit_endpoint: "demo"
        )

      theirs =
        sdk_url("imagekit", "/cat.jpg", %{
          "transformation" => [
            %{
              "width" => "600",
              "height" => "400",
              "crop" => "extract",
              "format" => "webp",
              "quality" => "75"
            }
          ]
        })

      assert_path_token_set_equal(ours, theirs)
    end

    test "default-trim divergence is intentional" do
      # ImageKit's official SDK always emits `q-<n>` even when
      # `n` is the default (80); our projector trims defaults to
      # keep URLs short. The trimmed URL decodes to the same
      # IR, so we deliberately diverge.
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 600}],
        output: %Ops.Format{type: :webp, quality: 80}
      }

      ours =
        URL.imagekit(pipeline,
          source_path: "/cat.jpg",
          host: "https://ik.imagekit.io",
          imagekit_endpoint: "demo"
        )

      theirs =
        sdk_url("imagekit", "/cat.jpg", %{
          "transformation" => [%{"width" => "600", "format" => "webp", "quality" => "80"}]
        })

      ours_set = MapSet.new(path_tokens(ours))
      theirs_set = MapSet.new(path_tokens(theirs))

      # `theirs` has the same tokens as `ours` PLUS `q-80`.
      assert MapSet.subset?(ours_set, theirs_set)
      assert MapSet.difference(theirs_set, ours_set) == MapSet.new(["q-80"])
    end

    test "face-aware crop with z (face_zoom)" do
      pipeline = %Pipeline{
        ops: [%Ops.Resize{width: 400, fit: :cover, gravity: :face, face_zoom: 0.6}],
        output: nil
      }

      ours =
        URL.imagekit(pipeline,
          source_path: "/portrait.jpg",
          host: "https://ik.imagekit.io",
          imagekit_endpoint: "demo"
        )

      theirs =
        sdk_url("imagekit", "/portrait.jpg", %{
          "transformation" => [
            %{
              "width" => "400",
              "crop" => "extract",
              "focus" => "face",
              "zoom" => "0.6"
            }
          ]
        })

      assert_path_token_set_equal(ours, theirs)
    end
  end

  # ── helpers ─────────────────────────────────────────────────────

  # Shell out to the Node helper, send one JSON request on stdin,
  # read one JSON response on stdout. Each invocation spawns a
  # fresh Node process — wasteful at scale but simple and
  # rebuilds-clean. ~12 tests × ~120 ms each = under 2 s total.
  defp sdk_url(provider, source, intent) do
    request = %{"provider" => provider, "source" => source, "intent" => intent}
    json = Jason.encode!(request)

    port =
      Port.open(
        {:spawn_executable, System.find_executable("node")},
        [
          :binary,
          :exit_status,
          {:args, ["bin/build-url.js"]},
          {:cd, @sdk_dir}
        ]
      )

    Port.command(port, json <> "\n")

    case collect_line(port, "") do
      {:ok, line} ->
        case Jason.decode!(String.trim(line)) do
          %{"url" => url} -> url
          %{"error" => err} -> flunk("Node SDK helper returned error: #{err}")
        end

      :timeout ->
        flunk("Node SDK helper timed out")
    end
  end

  defp collect_line(port, acc) do
    receive do
      {^port, {:data, chunk}} ->
        case String.split(acc <> chunk, "\n", parts: 2) do
          [line, _rest] ->
            send(port, {self(), :close})
            {:ok, line}

          [partial] ->
            collect_line(port, partial)
        end

      {^port, {:exit_status, _}} ->
        if acc == "", do: :timeout, else: {:ok, acc}
    after
      10_000 ->
        send(port, {self(), :close})
        :timeout
    end
  end

  # Compare two path-prefix-style URLs (Cloudinary, ImageKit) by
  # extracting the comma-separated token list from the options
  # segment and comparing as sets. Different sort orders compare
  # equal.
  defp assert_path_token_set_equal(ours, theirs) do
    ours_tokens = path_tokens(ours)
    theirs_tokens = path_tokens(theirs)

    assert MapSet.new(ours_tokens) == MapSet.new(theirs_tokens),
           """
           Token sets differ.
                 ours: #{inspect(ours_tokens)}
               theirs: #{inspect(theirs_tokens)}
                  ours URL: #{ours}
                theirs URL: #{theirs}
           """
  end

  defp path_tokens(url) do
    cond do
      # Cloudinary: …/image/upload/<comma-separated>/<source>
      String.contains?(url, "/image/upload/") ->
        url
        |> String.split("/image/upload/", parts: 2)
        |> List.last()
        |> String.split("/", parts: 2)
        |> List.first()
        |> String.split(",")

      # ImageKit: …/<endpoint>/tr:<comma-separated>/<source>
      String.contains?(url, "/tr:") ->
        url
        |> String.split("/tr:", parts: 2)
        |> List.last()
        |> String.split("/", parts: 2)
        |> List.first()
        |> String.split(",")

      true ->
        []
    end
  end

  # Compare two query-string-style URLs (imgix) by parsing the
  # query and comparing as a map. Order is irrelevant.
  defp assert_query_set_equal(ours, theirs) do
    ours_q = url_query(ours)
    theirs_q = url_query(theirs)

    assert ours_q == theirs_q,
           """
           Query maps differ.
                 ours: #{inspect(ours_q)}
               theirs: #{inspect(theirs_q)}
                  ours URL: #{ours}
                theirs URL: #{theirs}
           """
  end

  defp url_query(url) do
    case String.split(url, "?", parts: 2) do
      [_, query] -> URI.decode_query(query)
      [_] -> %{}
    end
  end
end
