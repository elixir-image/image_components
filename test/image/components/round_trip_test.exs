defmodule Image.Components.RoundTripTest do
  @moduledoc """
  Property-based round-trip tests: project a `Pipeline` to a URL via
  `Image.Components.URL.<provider>/2`, extract the options segment,
  parse it back via the matching `image_plug` provider, and assert
  the resulting Pipeline equals the input.

  This catches projector/parser drift inside the codebase — cases
  where a parser token was added without the symmetric projector
  emit (or vice versa) — but does not validate against the real
  CDN's URL grammar. For real-CDN validation see
  `live_cdn_test.exs` and `cross_sdk_test.exs`.

  Tagged `:round_trip`; included by default. Run only the round-trip
  suite with `mix test --only round_trip`.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Image.Components.URL
  alias Image.Plug.Pipeline
  alias Image.Plug.Pipeline.Ops

  alias Image.Plug.Provider.Cloudflare.Options, as: CloudflareOptions
  alias Image.Plug.Provider.Cloudinary.Options, as: CloudinaryOptions
  alias Image.Plug.Provider.Imgix.Options, as: ImgixOptions
  alias Image.Plug.Provider.ImageKit.Options, as: ImageKitOptions

  @moduletag :round_trip

  # Generators are scoped per provider — every value avoids the
  # provider's default so no token gets dropped on emit. Without
  # this discipline the round-trip would lose the field on the
  # projection step and the parsed pipeline would legitimately
  # differ from the input (a "missing token = default value"
  # invariant).

  defp resize_generator(provider) do
    gen all width <- one_of([constant(nil), integer(50..2000)]),
            height <- one_of([constant(nil), integer(50..2000)]),
            fit <- non_default_fit(provider),
            gravity <- non_default_gravity(provider),
            dpr <- integer(1..3) do
      %Ops.Resize{
        width: width,
        height: height,
        fit: fit,
        gravity: gravity,
        upscale?: true,
        dpr: dpr,
        face_zoom: 0.0
      }
    end
  end

  # Per-provider safe fit set — only values that round-trip
  # idempotently. Several IR fit values collide on the wire
  # because the CDN URL grammars have fewer fit tokens than the
  # IR's six. For example Cloudflare's `scale-down` token decodes
  # to `:contain` (the IR default), so projecting `:scale_down`
  # and parsing back yields `:contain` — a documented lossy
  # mapping in the conformance guide. Excluded here because the
  # round-trip property only holds for the safe subset.
  defp non_default_fit(:cloudflare), do: member_of([:cover, :crop, :pad])
  defp non_default_fit(:cloudinary), do: member_of([:cover, :pad, :scale_down, :squeeze])
  defp non_default_fit(:imgix), do: member_of([:cover, :pad, :scale_down, :squeeze])
  defp non_default_fit(:imagekit), do: member_of([:pad, :scale_down, :squeeze])

  defp non_default_gravity(_provider) do
    member_of([:auto, :face, :north, :south, :east, :west])
  end

  defp format_generator do
    gen all type <- member_of([:auto, :jpeg, :png, :webp, :avif]),
            quality <- integer(1..100) do
      %Ops.Format{
        type: type,
        quality: quality,
        metadata: :copyright,
        anim?: true,
        dpr: 1
      }
    end
  end

  describe "Cloudflare" do
    property "Resize round-trips" do
      check all resize <- resize_generator(:cloudflare),
                output <- format_generator() do
        pipeline = %Pipeline{ops: [resize], output: output}

        url = URL.cloudflare(pipeline, source_path: "/x.jpg")
        assert {:ok, parsed} = parse_cloudflare(url)

        assert_resize_equiv(parsed, resize)
      end
    end

    property "Blur round-trips" do
      check all sigma <- float(min: 0.5, max: 20.0) do
        pipeline = %Pipeline{ops: [%Ops.Blur{sigma: sigma}], output: nil}
        url = URL.cloudflare(pipeline, source_path: "/x.jpg")
        assert {:ok, parsed} = parse_cloudflare(url)

        # Cloudflare's blur token is `round(sigma * 2)`; the
        # parser inverts that. Equality is approximate within
        # rounding error.
        assert blur = Enum.find(parsed.ops, &match?(%Ops.Blur{}, &1))
        assert_in_delta blur.sigma, sigma, 1.0
      end
    end
  end

  describe "Cloudinary" do
    property "Resize round-trips" do
      check all resize <- resize_generator(:cloudinary),
                output <- format_generator() do
        pipeline = %Pipeline{ops: [resize], output: output}

        url = URL.cloudinary(pipeline, source_path: "/x.jpg")
        assert {:ok, parsed} = parse_cloudinary(url)

        assert_resize_equiv(parsed, resize)
      end
    end

    property "Vignette round-trips" do
      check all strength <- float(min: 0.05, max: 1.0) do
        pipeline = %Pipeline{ops: [%Ops.Vignette{strength: strength}], output: nil}
        url = URL.cloudinary(pipeline, source_path: "/x.jpg")
        assert {:ok, parsed} = parse_cloudinary(url)

        assert vignette = Enum.find(parsed.ops, &match?(%Ops.Vignette{}, &1))
        # Cloudinary's vignette is N% (0..100); we project as
        # round(strength * 100), the parser inverts as N/100.
        assert_in_delta vignette.strength, strength, 0.01
      end
    end
  end

  describe "imgix" do
    property "Resize round-trips" do
      check all resize <- resize_generator(:imgix),
                output <- format_generator() do
        pipeline = %Pipeline{ops: [resize], output: output}

        url = URL.imgix(pipeline, source_path: "/x.jpg")
        assert {:ok, parsed} = parse_imgix(url)

        assert_resize_equiv(parsed, resize, drop_face_zoom: true)
      end
    end

    property "Adjust round-trips" do
      check all brightness <- float(min: 0.5, max: 1.99),
                contrast <- float(min: 0.5, max: 1.99) do
        adjust = %Ops.Adjust{
          brightness: brightness,
          contrast: contrast,
          saturation: 1.0,
          gamma: 1.0
        }

        url = URL.imgix(%Pipeline{ops: [adjust], output: nil}, source_path: "/x.jpg")
        assert {:ok, parsed} = parse_imgix(url)

        assert parsed_adjust = Enum.find(parsed.ops, &match?(%Ops.Adjust{}, &1))
        assert_in_delta parsed_adjust.brightness, brightness, 0.02
        assert_in_delta parsed_adjust.contrast, contrast, 0.02
      end
    end
  end

  describe "ImageKit" do
    property "Resize (no adjust ops — ImageKit drops them) round-trips" do
      check all resize <- resize_generator(:imagekit),
                output <- format_generator() do
        pipeline = %Pipeline{ops: [resize], output: output}

        url = URL.imagekit(pipeline, source_path: "/x.jpg")
        assert {:ok, parsed} = parse_imagekit(url)

        assert_resize_equiv(parsed, resize)
      end
    end
  end

  # ── helpers ─────────────────────────────────────────────────────

  # Project URL → bare options string per provider, then parse.

  defp parse_cloudflare(url) do
    [_, opts, _] = Regex.run(~r{/cdn-cgi/image/([^/]+)/(.+)}, url)
    CloudflareOptions.parse(opts)
  end

  defp parse_cloudinary(url) do
    case Regex.run(~r{/[^/]+/image/upload/([^/]+)/(.+)}, url) do
      [_, opts, _] -> CloudinaryOptions.parse(opts)
      # No options segment (default-only pipeline) — empty parse.
      nil -> CloudinaryOptions.parse("")
    end
  end

  defp parse_imgix(url) do
    case String.split(url, "?", parts: 2) do
      [_path, query] -> ImgixOptions.parse(query)
      [_path] -> ImgixOptions.parse("")
    end
  end

  defp parse_imagekit(url) do
    case Regex.run(~r{/[^/]+/tr:([^/]+)/(.+)}, url) do
      [_, opts, _] -> ImageKitOptions.parse(opts)
      nil -> ImageKitOptions.parse("")
    end
  end

  # Compare a parsed pipeline's Resize op against the original.
  # `drop_face_zoom` for providers (imgix) whose URL grammar can't
  # carry face_zoom — the parsed value will be the IR default.
  defp assert_resize_equiv(parsed_pipeline, original, options \\ []) do
    parsed = Enum.find(parsed_pipeline.ops, &match?(%Ops.Resize{}, &1))
    assert parsed, "expected a Resize in parsed ops, got: #{inspect(parsed_pipeline.ops)}"

    assert parsed.width == original.width
    assert parsed.height == original.height
    assert parsed.fit == original.fit
    assert parsed.gravity == original.gravity
    assert parsed.dpr == original.dpr

    unless Keyword.get(options, :drop_face_zoom, false) do
      assert parsed.face_zoom == original.face_zoom
    end
  end
end
