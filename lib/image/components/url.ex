defmodule Image.Components.URL do
  @moduledoc """
  Per-provider URL builders.

  Projects a canonical `t:Image.Plug.Pipeline.t/0` onto the URL
  grammar of each supported provider. This is the inverse of the URL
  parsers in `image_plug`'s provider modules: those parsers
  consume URLs and produce a `Pipeline`; these builders go the
  other way — `Pipeline` → provider-specific URL string.

  Five providers are supported: four commercial image CDNs
  (Cloudflare Images, Cloudinary, imgix, ImageKit) plus
  [IIIF Image API 3.0](https://iiif.io/api/image/3.0/), the open
  standard implemented by cultural-heritage and academic image
  servers (Cantaloupe, Loris, IIPImage, Wellcome, Library of
  Congress, …). The same IR drives all five grammars, so an
  option set produces five URLs with comparable semantics — modulo
  the per-provider feature gaps.

  ## Coverage

  Implements the round-trip subset shared by the five providers:
  resize (width/height/fit/gravity/dpr), format/quality,
  blur/sharpen, brightness/contrast/saturation/gamma, rotate,
  trim, background, plus IIIF-specific `region` and named-quality
  (`gray`/`bitonal`) tokens. Operations not natively expressible
  in a given provider's URL grammar are dropped silently and
  documented in the corresponding `image_plug` provider's
  conformance guide.

  ## Provider semantic differences

  The five providers do not all express adjust effects the same
  way:

    * **Cloudflare** takes brightness/contrast/saturation/gamma
      as raw multipliers (the same units as the IR; `1.0` = no
      change).

    * **Cloudinary** and **imgix** take centred percentages in
      `-100..100`, where `0` = no change. The builders below
      convert: an IR value of `1.4` becomes `e_contrast:40` for
      Cloudinary and `con=40` for imgix.

    * **ImageKit** has only an unparameterised `e-contrast`
      toggle (auto-contrast). Brightness/contrast/saturation/
      gamma multipliers cannot be faithfully expressed in
      ImageKit URL form, so they are silently dropped — no
      approximation, by design. See
      `guides/imagekit_conformance.md` in `image_plug`.

    * **IIIF** has no parameterised adjust effects at all. Only
      `Adjust{saturation: 0.0}` round-trips, via the `gray`
      quality token in the URL's quality segment; everything else
      (brightness, contrast, gamma, non-zero saturation) is
      silently dropped. See `guides/iiif_conformance.md` in
      `image_plug`.

  ## Examples

      iex> alias Image.Plug.Pipeline
      iex> alias Image.Plug.Pipeline.Ops
      iex> p = %Pipeline{ops: [%Ops.Resize{width: 600}], output: %Ops.Format{type: :webp, quality: 80}}
      iex> Image.Components.URL.cloudflare(p, source_path: "/sample.jpg")
      "/cdn-cgi/image/width=600,format=webp,quality=80/sample.jpg"

  """

  alias Image.Plug.Pipeline
  alias Image.Plug.Pipeline.Ops

  @typedoc """
  Per-builder options, shared across the four projectors.

    * `:source_path` — the URL-relative source path. Cloudflare,
      Cloudinary, and ImageKit append this after the options
      segment; imgix prepends it before the query string.
      Defaults to `\"/sample.jpg\"`.

    * `:host` — when supplied, prepended verbatim (e.g.
      `\"https://playground.example.com\"` or just
      `\"/img\"` to scope under a path). Default `\"\"` — relative
      URL.

    * `:cloudinary_account` — Cloudinary's `<cloud-name>`
      segment. Default `\"demo\"`.

    * `:imagekit_endpoint` — ImageKit's per-account endpoint
      segment. Default `\"demo\"`.

  """
  @type options :: keyword()

  @doc """
  Projects the pipeline onto the Cloudflare Images URL grammar: `<host>/cdn-cgi/image/<options>/<source>`.

  ### Arguments

  * `pipeline` is an `Image.Plug.Pipeline.t()`.

  * `options` is a keyword list — see the Options section.

  ### Options

  * `:source_path` is the URL-relative source path. Defaults to `\"/sample.jpg\"`.

  * `:host` is prepended verbatim — e.g. `\"https://playground.example.com\"` or `\"/img\"` to scope under a path. Defaults to `\"\"` (relative URL).

  ### Returns

  * The projected URL as a string. Cloudflare requires at least one option; when the pipeline projects to nothing, `format=auto` (a no-op) is emitted.

  ### Examples

      iex> alias Image.Plug.Pipeline
      iex> alias Image.Plug.Pipeline.Ops
      iex> p = %Pipeline{ops: [%Ops.Resize{width: 200}], output: nil}
      iex> Image.Components.URL.cloudflare(p, source_path: "/abc.jpg")
      "/cdn-cgi/image/width=200/abc.jpg"

  """
  @spec cloudflare(Pipeline.t(), options()) :: String.t()
  def cloudflare(%Pipeline{} = pipeline, options \\ []) do
    options_segment = pipeline |> cloudflare_options() |> Enum.join(",")
    source = source_path(options)
    host = Keyword.get(options, :host, "")

    # Cloudflare requires a non-empty options segment; emit
    # `format=auto` (the default and a no-op) when we'd otherwise
    # produce nothing.
    url =
      case options_segment do
        "" -> "#{host}/cdn-cgi/image/format=auto/#{trim_leading_slash(source)}"
        seg -> "#{host}/cdn-cgi/image/#{seg}/#{trim_leading_slash(source)}"
      end

    maybe_sign(url, options, :cloudflare)
  end

  @doc """
  Projects the pipeline onto the Cloudinary URL grammar: `<host>/<account>/image/upload/<options>/<source>`.

  ### Arguments

  * `pipeline` is an `Image.Plug.Pipeline.t()`.

  * `options` is a keyword list — see the Options section.

  ### Options

  * `:source_path` is the URL-relative source path. Defaults to `\"/sample.jpg\"`.

  * `:host` is prepended verbatim. Defaults to `\"\"` (relative URL).

  * `:cloudinary_account` is the `<cloud-name>` segment. Defaults to `\"demo\"`.

  ### Returns

  * The projected URL as a string. When the pipeline projects to no options, the `tr:` segment is omitted and the URL collapses to `<host>/<account>/image/upload/<source>`.

  ### Examples

      iex> alias Image.Plug.Pipeline
      iex> alias Image.Plug.Pipeline.Ops
      iex> p = %Pipeline{ops: [%Ops.Resize{width: 200}], output: nil}
      iex> Image.Components.URL.cloudinary(p, source_path: "/abc.jpg")
      "/demo/image/upload/w_200/abc.jpg"

  """
  @spec cloudinary(Pipeline.t(), options()) :: String.t()
  def cloudinary(%Pipeline{} = pipeline, options \\ []) do
    options_segment = pipeline |> cloudinary_options() |> Enum.join(",")
    source = source_path(options) |> trim_leading_slash()
    account = Keyword.get(options, :cloudinary_account, "demo")
    host = Keyword.get(options, :host, "")

    url =
      case options_segment do
        "" -> "#{host}/#{account}/image/upload/#{source}"
        seg -> "#{host}/#{account}/image/upload/#{seg}/#{source}"
      end

    maybe_sign(url, options, :cloudinary)
  end

  @doc """
  Projects the pipeline onto the imgix URL grammar: `<host>/<source>?<options>`.

  ### Arguments

  * `pipeline` is an `Image.Plug.Pipeline.t()`.

  * `options` is a keyword list — see the Options section.

  ### Options

  * `:source_path` is the URL-relative source path. Defaults to `\"/sample.jpg\"`.

  * `:host` is prepended verbatim. Defaults to `\"\"` (relative URL).

  ### Returns

  * The projected URL as a string. When the pipeline projects to no options, the `?…` query string is omitted and only `<host><source>` remains.

  ### Examples

      iex> alias Image.Plug.Pipeline
      iex> alias Image.Plug.Pipeline.Ops
      iex> p = %Pipeline{ops: [%Ops.Resize{width: 200}], output: nil}
      iex> Image.Components.URL.imgix(p, source_path: "/abc.jpg")
      "/abc.jpg?w=200"

  """
  @spec imgix(Pipeline.t(), options()) :: String.t()
  def imgix(%Pipeline{} = pipeline, options \\ []) do
    query = pipeline |> imgix_options() |> URI.encode_query()
    source = source_path(options)
    host = Keyword.get(options, :host, "")

    url =
      case query do
        "" -> "#{host}#{source}"
        q -> "#{host}#{source}?#{q}"
      end

    maybe_sign(url, options, :imgix)
  end

  @doc """
  Projects the pipeline onto the ImageKit URL grammar: `<host>/<endpoint>/tr:<options>/<source>`.

  ### Arguments

  * `pipeline` is an `Image.Plug.Pipeline.t()`.

  * `options` is a keyword list — see the Options section.

  ### Options

  * `:source_path` is the URL-relative source path. Defaults to `\"/sample.jpg\"`.

  * `:host` is prepended verbatim. Defaults to `\"\"` (relative URL).

  * `:imagekit_endpoint` is the per-account endpoint segment. Defaults to `\"demo\"`.

  ### Returns

  * The projected URL as a string. When the pipeline projects to no options, the `tr:` segment is omitted and the URL collapses to `<host>/<endpoint>/<source>`.

  ### Examples

      iex> alias Image.Plug.Pipeline
      iex> alias Image.Plug.Pipeline.Ops
      iex> p = %Pipeline{ops: [%Ops.Resize{width: 200}], output: nil}
      iex> Image.Components.URL.imagekit(p, source_path: "/abc.jpg")
      "/demo/tr:w-200/abc.jpg"

  """
  @spec imagekit(Pipeline.t(), options()) :: String.t()
  def imagekit(%Pipeline{} = pipeline, options \\ []) do
    options_segment = pipeline |> imagekit_options() |> Enum.join(",")
    source = source_path(options) |> trim_leading_slash()
    endpoint = Keyword.get(options, :imagekit_endpoint, "demo")
    host = Keyword.get(options, :host, "")

    url =
      case options_segment do
        "" -> "#{host}/#{endpoint}/#{source}"
        seg -> "#{host}/#{endpoint}/tr:#{seg}/#{source}"
      end

    maybe_sign(url, options, :imagekit)
  end

  @doc """
  Projects the pipeline onto the [IIIF Image API 3.0](https://iiif.io/api/image/3.0/) URL grammar: `<host><prefix>/<identifier>/<region>/<size>/<rotation>/<quality>.<format>`.

  ### Arguments

  * `pipeline` is an `Image.Plug.Pipeline.t()`.

  * `options` is a keyword list — see the Options section.

  ### Options

  * `:source_path` is the URL-relative source path used as the IIIF identifier. Leading `/` is stripped; embedded `/` characters are percent-encoded as `%2F` per the spec. Defaults to `\"/sample.jpg\"`.

  * `:host` is prepended verbatim — e.g. `\"https://iiif.example.org\"` or `\"\"` for a relative URL.

  * `:iiif_prefix` is the server's IIIF version prefix (the `/{prefix}` segment in the spec). Typical values: `\"/iiif/3\"` for an Image API 3.0 server, `\"/cantaloupe/iiif/3\"` for Cantaloupe deployments. Defaults to `\"/iiif/3\"`.

  * `:iiif_format` is the format extension used when the pipeline's output `Format.type` is `:auto` (IIIF requires an explicit format in the URL). Defaults to `:jpeg`.

  ### Returns

  * The projected URL as a string. The five positional segments are always emitted: `region`, `size`, `rotation`, `quality.format`. A pipeline with no transforms produces `<host>/iiif/3/<id>/full/max/0/default.jpg`.

  ### Conformance gaps

  IIIF's URL grammar is narrower than the IR. The following ops project to `default` / `max` / `full` rather than the requested transform — see `guides/iiif.md` (in `image_plug`) for the per-op detail:

    * `Resize{fit: :cover}` — IIIF cannot express "scale-to-fill plus centred crop" in one URL. Drop and use `:contain` or `:squeeze` instead, or supply an explicit `Crop` op for the region you want.
    * `Blur`, `Sharpen`, `Vignette`, `Tint`, `Background`, non-grayscale `Adjust`, `face_zoom`, `gravity` — silently dropped. The IIIF spec scopes to a small set of geometric and quality transforms; effects are out of scope.

  ### Examples

      iex> alias Image.Plug.Pipeline
      iex> alias Image.Plug.Pipeline.Ops
      iex> p = %Pipeline{ops: [%Ops.Resize{width: 600}], output: %Ops.Format{type: :jpeg, quality: 80}}
      iex> Image.Components.URL.iiif(p, source_path: "/cat.jpg", host: "https://iiif.example.org")
      "https://iiif.example.org/iiif/3/cat.jpg/full/^600,/0/default.jpg"

      iex> alias Image.Plug.Pipeline
      iex> Image.Components.URL.iiif(%Pipeline{ops: [], output: nil}, source_path: "/cat.jpg")
      "/iiif/3/cat.jpg/full/max/0/default.jpg"

  """
  @spec iiif(Pipeline.t(), options()) :: String.t()
  def iiif(%Pipeline{} = pipeline, options \\ []) do
    identifier = source_path(options) |> trim_leading_slash() |> iiif_encode_identifier()
    host = Keyword.get(options, :host, "")
    prefix = Keyword.get(options, :iiif_prefix, "/iiif/3")
    fmt_default = Keyword.get(options, :iiif_format, :jpeg)

    region = iiif_region(find_op(pipeline, Ops.Crop))
    size = iiif_size(find_op(pipeline, Ops.Resize))
    rotation = iiif_rotation(find_op(pipeline, Ops.Rotate))
    quality = iiif_quality(pipeline)
    format = iiif_format_extension(pipeline.output, fmt_default)

    url = "#{host}#{prefix}/#{identifier}/#{region}/#{size}/#{rotation}/#{quality}.#{format}"
    maybe_sign(url, options, :iiif)
  end

  # ─── shared helpers ──────────────────────────────────────────────

  defp source_path(options), do: Keyword.get(options, :source_path, "/sample.jpg")
  defp trim_leading_slash("/" <> rest), do: rest
  defp trim_leading_slash(s), do: s

  defp find_op(pipeline, module) do
    Enum.find(pipeline.ops, fn op -> op.__struct__ == module end)
  end

  # Dispatch a built URL to the right per-provider signer when
  # `:sign` is supplied in the options. The signer takes the
  # request path-and-query (origin stripped, since back-end
  # verifiers ignore the origin) and returns it with the
  # vendor-specific signature appended. Each vendor uses a
  # different algorithm and parameter name — see the per-provider
  # `Image.Components.Signing.*` modules.
  defp maybe_sign(url, options, provider) do
    case Keyword.get(options, :sign) do
      nil ->
        url

      [_ | _] = keys ->
        sign_options =
          case Keyword.get(options, :sign_expires_at) do
            nil -> []
            value -> [expires_at: value]
          end

        {origin, path} = split_origin(url)
        signer = signer_for(provider)
        origin <> signer.sign(path, keys, sign_options)
    end
  end

  defp signer_for(:cloudflare), do: Image.Components.Signing
  defp signer_for(:cloudinary), do: Image.Components.Signing.Cloudinary
  defp signer_for(:imgix), do: Image.Components.Signing.Imgix
  defp signer_for(:imagekit), do: Image.Components.Signing.ImageKit
  # IIIF doesn't have a standard URL-signing scheme — IIIF Auth API
  # 2.0 uses cookie/token-based access control at the protocol
  # level, not URL signatures. Fall back to the Cloudflare-style
  # generic HMAC for callers that want SOMETHING; document this
  # as not standardised.
  defp signer_for(:iiif), do: Image.Components.Signing

  defp split_origin("http://" <> _ = url), do: split_origin_at_path(url)
  defp split_origin("https://" <> _ = url), do: split_origin_at_path(url)
  defp split_origin(path), do: {"", path}

  defp split_origin_at_path(url) do
    case String.split(url, "/", parts: 4) do
      [scheme, "", host, rest] -> {scheme <> "//" <> host, "/" <> rest}
      _ -> {"", url}
    end
  end

  # ─── Cloudflare projection ────────────────────────────────────────

  defp cloudflare_options(pipeline) do
    [
      cloudflare_resize(find_op(pipeline, Ops.Resize)),
      cloudflare_format(pipeline.output),
      cloudflare_adjust(find_op(pipeline, Ops.Adjust)),
      cloudflare_blur_sharpen(pipeline),
      cloudflare_rotate(find_op(pipeline, Ops.Rotate)),
      cloudflare_trim(find_op(pipeline, Ops.Trim)),
      cloudflare_background(find_op(pipeline, Ops.Background))
    ]
    |> Enum.concat()
  end

  defp cloudflare_resize(nil), do: []

  defp cloudflare_resize(%Ops.Resize{} = r) do
    []
    |> opt("width", r.width)
    |> opt("height", r.height)
    |> opt_unless_default("fit", r.fit && cloudflare_fit(r.fit), "scale-down")
    |> opt_unless_default("gravity", r.gravity && cloudflare_gravity(r.gravity), "center")
    |> opt_unless_default("dpr", r.dpr, 1)
    |> opt_unless_default("face-zoom", r.face_zoom, 0.0)
  end

  defp cloudflare_fit(:contain), do: "scale-down"
  defp cloudflare_fit(:cover), do: "cover"
  defp cloudflare_fit(:crop), do: "crop"
  defp cloudflare_fit(:pad), do: "pad"
  defp cloudflare_fit(:scale_down), do: "scale-down"
  defp cloudflare_fit(:squeeze), do: "contain"
  defp cloudflare_fit(other), do: to_string(other)

  defp cloudflare_gravity(:center), do: "center"
  defp cloudflare_gravity(:auto), do: "auto"
  defp cloudflare_gravity(:face), do: "face"
  defp cloudflare_gravity(:north), do: "top"
  defp cloudflare_gravity(:south), do: "bottom"
  defp cloudflare_gravity(:east), do: "right"
  defp cloudflare_gravity(:west), do: "left"
  defp cloudflare_gravity({:xy, x, y}), do: "#{Float.round(x, 2)}x#{Float.round(y, 2)}"
  defp cloudflare_gravity(other), do: to_string(other)

  defp cloudflare_format(nil), do: []

  defp cloudflare_format(%Ops.Format{} = f) do
    []
    |> opt_unless_default("format", cloudflare_format_atom(f.type), "auto")
    |> opt_unless_default("quality", f.quality, 85)
    |> opt_unless_default("metadata", f.metadata, :copyright)
  end

  defp cloudflare_format_atom(:auto), do: "auto"
  defp cloudflare_format_atom(:jpeg), do: "jpeg"
  defp cloudflare_format_atom(:baseline_jpeg), do: "baseline-jpeg"
  defp cloudflare_format_atom(:png), do: "png"
  defp cloudflare_format_atom(:webp), do: "webp"
  defp cloudflare_format_atom(:avif), do: "avif"
  defp cloudflare_format_atom(other), do: to_string(other)

  defp cloudflare_adjust(nil), do: []

  defp cloudflare_adjust(%Ops.Adjust{} = a) do
    # Cloudflare takes brightness/contrast/saturation/gamma as raw
    # multipliers where 1.0 means "no change" (the same units as the
    # IR). Cloudinary and imgix want centred percentages — handled
    # separately in the per-provider sections below.
    []
    |> opt_unless_default("brightness", format_multiplier(a.brightness), "1")
    |> opt_unless_default("contrast", format_multiplier(a.contrast), "1")
    |> opt_unless_default("saturation", format_multiplier(a.saturation), "1")
    |> opt_unless_default("gamma", format_multiplier(a.gamma), "1")
  end

  defp cloudflare_blur_sharpen(pipeline) do
    blur =
      case find_op(pipeline, Ops.Blur) do
        %Ops.Blur{sigma: s} when s > 0 -> opt([], "blur", round(s * 2))
        _ -> []
      end

    sharpen =
      case find_op(pipeline, Ops.Sharpen) do
        %Ops.Sharpen{sigma: s} when s > 0 -> opt([], "sharpen", round(s * 10))
        _ -> []
      end

    blur ++ sharpen
  end

  defp cloudflare_rotate(nil), do: []
  defp cloudflare_rotate(%Ops.Rotate{angle: 0}), do: []
  defp cloudflare_rotate(%Ops.Rotate{angle: a}), do: opt([], "rotate", a)

  defp cloudflare_trim(nil), do: []
  defp cloudflare_trim(%Ops.Trim{mode: :border}), do: opt([], "trim", "border")
  defp cloudflare_trim(_), do: []

  defp cloudflare_background(nil), do: []

  defp cloudflare_background(%Ops.Background{color: color}),
    do: opt([], "background", to_string(color))

  # ─── generic opt helpers ──────────────────────────────────────────

  defp opt(acc, _key, nil), do: acc
  defp opt(acc, _key, false), do: acc
  defp opt(acc, key, value), do: acc ++ ["#{key}=#{value}"]

  defp opt_unless_default(acc, _key, value, default) when value == default, do: acc
  defp opt_unless_default(acc, key, value, _default), do: opt(acc, key, value)

  # Cloudflare expects raw multipliers as compact numeric strings
  # (e.g. `1.4` not `1.4000`). Render integers without a decimal.
  defp format_multiplier(v) when is_number(v) do
    cond do
      v == trunc(v) -> Integer.to_string(trunc(v))
      true -> :erlang.float_to_binary(v * 1.0, [:compact, decimals: 4])
    end
  end

  # ─── Cloudinary projection ────────────────────────────────────────

  defp cloudinary_options(pipeline) do
    [
      cloudinary_resize(find_op(pipeline, Ops.Resize)),
      cloudinary_format(pipeline.output),
      cloudinary_adjust_effects(find_op(pipeline, Ops.Adjust)),
      cloudinary_blur_sharpen(pipeline),
      cloudinary_vignette(find_op(pipeline, Ops.Vignette))
    ]
    |> Enum.concat()
  end

  defp cloudinary_vignette(nil), do: []

  defp cloudinary_vignette(%Ops.Vignette{strength: s}) when s > 0,
    do: ["e_vignette:#{round(s * 100)}"]

  defp cloudinary_vignette(_), do: []

  defp cloudinary_resize(nil), do: []

  defp cloudinary_resize(%Ops.Resize{} = r) do
    []
    |> cl_opt("w", r.width)
    |> cl_opt("h", r.height)
    |> cl_opt_unless_default("dpr", r.dpr, 1)
    |> cl_opt_unless_default("c", cloudinary_fit(r.fit), "fit")
    |> cl_opt_unless_default("g", cloudinary_gravity(r.gravity), "center")
    # `z_<float>` matches the new Cloudinary URL parser in
    # image_plug; face-zoom in `[0, 1]`. Only meaningful with
    # `g_face` but emitted regardless to mirror the IR.
    |> cl_opt_unless_default("z", cloudinary_face_zoom(r.face_zoom), nil)
  end

  defp cloudinary_face_zoom(z) when is_number(z) and z > 0.0 do
    :erlang.float_to_binary(z * 1.0, [:compact, decimals: 4])
  end

  defp cloudinary_face_zoom(_), do: nil

  defp cloudinary_fit(:contain), do: "fit"
  defp cloudinary_fit(:cover), do: "fill"
  defp cloudinary_fit(:crop), do: "crop"
  defp cloudinary_fit(:pad), do: "pad"
  defp cloudinary_fit(:scale_down), do: "limit"
  defp cloudinary_fit(:squeeze), do: "scale"
  defp cloudinary_fit(_), do: nil

  defp cloudinary_gravity(:center), do: "center"
  defp cloudinary_gravity(:auto), do: "auto"
  defp cloudinary_gravity(:face), do: "face"
  defp cloudinary_gravity(:north), do: "north"
  defp cloudinary_gravity(:north_east), do: "north_east"
  defp cloudinary_gravity(:north_west), do: "north_west"
  defp cloudinary_gravity(:south), do: "south"
  defp cloudinary_gravity(:south_east), do: "south_east"
  defp cloudinary_gravity(:south_west), do: "south_west"
  defp cloudinary_gravity(:east), do: "east"
  defp cloudinary_gravity(:west), do: "west"
  defp cloudinary_gravity({:xy, _, _}), do: "xy_center"
  defp cloudinary_gravity(_), do: nil

  defp cloudinary_format(nil), do: []

  defp cloudinary_format(%Ops.Format{} = f) do
    []
    |> cl_opt_unless_default("f", cloudinary_format_atom(f.type), "auto")
    |> cl_opt_unless_default("q", f.quality, 85)
  end

  defp cloudinary_format_atom(:auto), do: "auto"
  defp cloudinary_format_atom(:jpeg), do: "jpg"
  defp cloudinary_format_atom(:png), do: "png"
  defp cloudinary_format_atom(:webp), do: "webp"
  defp cloudinary_format_atom(:avif), do: "avif"
  defp cloudinary_format_atom(_), do: nil

  defp cloudinary_adjust_effects(nil), do: []

  defp cloudinary_adjust_effects(%Ops.Adjust{} = a) do
    []
    |> cloudinary_centered_effect("brightness", a.brightness)
    |> cloudinary_centered_effect("contrast", a.contrast)
    |> cloudinary_centered_effect("saturation", a.saturation)
    |> cloudinary_centered_effect("gamma", a.gamma)
  end

  defp cloudinary_centered_effect(acc, _name, value) when value == 1.0, do: acc

  defp cloudinary_centered_effect(acc, name, value) do
    pct = round((value - 1.0) * 100)
    acc ++ ["e_#{name}:#{pct}"]
  end

  defp cloudinary_blur_sharpen(pipeline) do
    blur =
      case find_op(pipeline, Ops.Blur) do
        %Ops.Blur{sigma: s} when s > 0 -> ["e_blur:#{round(s * 100)}"]
        _ -> []
      end

    sharpen =
      case find_op(pipeline, Ops.Sharpen) do
        %Ops.Sharpen{sigma: s} when s > 0 -> ["e_sharpen:#{round(s * 10)}"]
        _ -> []
      end

    blur ++ sharpen
  end

  defp cl_opt(acc, _key, nil), do: acc
  defp cl_opt(acc, key, value), do: acc ++ ["#{key}_#{value}"]

  defp cl_opt_unless_default(acc, _key, value, default) when value == default, do: acc
  defp cl_opt_unless_default(acc, key, value, _default), do: cl_opt(acc, key, value)

  # ─── imgix projection ─────────────────────────────────────────────

  defp imgix_options(pipeline) do
    [
      imgix_resize(find_op(pipeline, Ops.Resize)),
      imgix_format(pipeline.output),
      imgix_adjust(find_op(pipeline, Ops.Adjust)),
      imgix_blur_sharpen(pipeline),
      imgix_rotate(find_op(pipeline, Ops.Rotate)),
      imgix_trim(find_op(pipeline, Ops.Trim)),
      imgix_background(find_op(pipeline, Ops.Background)),
      imgix_tint(find_op(pipeline, Ops.Tint))
    ]
    |> Enum.concat()
  end

  # imgix's `monochrome=<hex>` is the closest analog to a tint
  # op — it produces a luminance-tinted monochrome. `Ops.Tint`'s
  # type is `[non_neg_integer()]`; the `Image.Components.image/1`
  # component normalises hex strings into the list form before
  # building the pipeline, so we only need to handle that here.
  defp imgix_tint(nil), do: []
  defp imgix_tint(%Ops.Tint{color: [r, g, b]}), do: qs([], "monochrome", rgb_to_hex(r, g, b))
  defp imgix_tint(_), do: []

  defp rgb_to_hex(r, g, b) do
    [r, g, b]
    |> Enum.map_join("", fn n ->
      n |> Integer.to_string(16) |> String.pad_leading(2, "0") |> String.downcase()
    end)
  end

  defp imgix_resize(nil), do: []

  defp imgix_resize(%Ops.Resize{} = r) do
    []
    |> qs("w", r.width)
    |> qs("h", r.height)
    |> qs_unless_default("dpr", r.dpr, 1)
    |> qs_unless_default("fit", imgix_fit(r.fit), "clip")
    |> qs("crop", imgix_crop(r.gravity))
  end

  defp imgix_fit(:contain), do: "clip"
  defp imgix_fit(:cover), do: "crop"
  defp imgix_fit(:crop), do: "crop"
  defp imgix_fit(:pad), do: "fill"
  defp imgix_fit(:scale_down), do: "max"
  defp imgix_fit(:squeeze), do: "scale"
  defp imgix_fit(_), do: nil

  defp imgix_crop(:center), do: nil
  defp imgix_crop(:north), do: "top"
  defp imgix_crop(:south), do: "bottom"
  defp imgix_crop(:east), do: "right"
  defp imgix_crop(:west), do: "left"
  defp imgix_crop(:north_east), do: "top,right"
  defp imgix_crop(:north_west), do: "top,left"
  defp imgix_crop(:south_east), do: "bottom,right"
  defp imgix_crop(:south_west), do: "bottom,left"
  defp imgix_crop(:face), do: "faces"
  defp imgix_crop(:auto), do: "entropy"
  defp imgix_crop({:xy, _, _}), do: "focalpoint"
  defp imgix_crop(_), do: nil

  defp imgix_format(nil), do: []

  defp imgix_format(%Ops.Format{type: :auto, quality: q}) do
    [{"auto", "format,compress"}] |> qs_unless_default("q", q, 75)
  end

  defp imgix_format(%Ops.Format{} = f) do
    []
    |> qs("fm", imgix_format_atom(f.type))
    |> qs_unless_default("q", f.quality, 75)
  end

  defp imgix_format_atom(:jpeg), do: "jpg"
  defp imgix_format_atom(:baseline_jpeg), do: "pjpg"
  defp imgix_format_atom(:png), do: "png"
  defp imgix_format_atom(:webp), do: "webp"
  defp imgix_format_atom(:avif), do: "avif"
  defp imgix_format_atom(_), do: nil

  defp imgix_adjust(nil), do: []

  defp imgix_adjust(%Ops.Adjust{} = a) do
    []
    |> qs_centered("bri", a.brightness)
    |> qs_centered("con", a.contrast)
    |> qs_centered("sat", a.saturation)
    |> qs_centered("gam", a.gamma)
  end

  defp qs_centered(acc, _key, value) when value == 1.0, do: acc
  defp qs_centered(acc, key, value), do: qs(acc, key, round((value - 1.0) * 100))

  defp imgix_blur_sharpen(pipeline) do
    blur =
      case find_op(pipeline, Ops.Blur) do
        %Ops.Blur{sigma: s} when s > 0 -> qs([], "blur", round(s * 100))
        _ -> []
      end

    sharpen =
      case find_op(pipeline, Ops.Sharpen) do
        %Ops.Sharpen{sigma: s} when s > 0 -> qs([], "sharp", round(s * 10))
        _ -> []
      end

    blur ++ sharpen
  end

  defp imgix_rotate(nil), do: []
  defp imgix_rotate(%Ops.Rotate{angle: 0}), do: []
  defp imgix_rotate(%Ops.Rotate{angle: a}), do: qs([], "rot", a)

  defp imgix_trim(nil), do: []
  defp imgix_trim(%Ops.Trim{mode: :border}), do: qs([], "trim", "auto")
  defp imgix_trim(_), do: []

  defp imgix_background(nil), do: []
  defp imgix_background(%Ops.Background{color: c}), do: qs([], "bg", to_string(c))

  defp qs(acc, _key, nil), do: acc
  defp qs(acc, key, value), do: acc ++ [{key, to_string(value)}]

  defp qs_unless_default(acc, _key, value, default) when value == default, do: acc
  defp qs_unless_default(acc, key, value, _default), do: qs(acc, key, value)

  # ─── ImageKit projection ──────────────────────────────────────────

  defp imagekit_options(pipeline) do
    [
      imagekit_resize(find_op(pipeline, Ops.Resize)),
      imagekit_format(pipeline.output),
      imagekit_blur_sharpen(pipeline),
      imagekit_rotate(find_op(pipeline, Ops.Rotate)),
      imagekit_background(find_op(pipeline, Ops.Background))
    ]
    |> Enum.concat()
  end

  defp imagekit_resize(nil), do: []

  defp imagekit_resize(%Ops.Resize{} = r) do
    []
    |> ik_opt("w", r.width)
    |> ik_opt("h", r.height)
    |> ik_opt_unless_default("dpr", r.dpr, 1)
    |> ik_opt_unless_default("c", imagekit_fit(r.fit), "maintain_ratio")
    |> ik_opt_unless_default("fo", imagekit_focus(r.gravity), "center")
    # ImageKit's `z-<float>` is face-zoom in `[0, 1]`. Only
    # meaningful with `fo-face`; emitted regardless to match the
    # IR.
    |> ik_opt_unless_default("z", imagekit_face_zoom(r.face_zoom), nil)
  end

  defp imagekit_face_zoom(z) when is_number(z) and z > 0.0 do
    :erlang.float_to_binary(z * 1.0, [:compact, decimals: 4])
  end

  defp imagekit_face_zoom(_), do: nil

  defp imagekit_fit(:contain), do: "maintain_ratio"
  defp imagekit_fit(:cover), do: "extract"
  defp imagekit_fit(:crop), do: "extract"
  defp imagekit_fit(:pad), do: "pad_resize"
  defp imagekit_fit(:scale_down), do: "at_max"
  defp imagekit_fit(:squeeze), do: "force"
  defp imagekit_fit(_), do: nil

  defp imagekit_focus(:center), do: "center"
  defp imagekit_focus(:auto), do: "auto"
  defp imagekit_focus(:face), do: "face"
  defp imagekit_focus(:north), do: "top"
  defp imagekit_focus(:south), do: "bottom"
  defp imagekit_focus(:east), do: "right"
  defp imagekit_focus(:west), do: "left"
  defp imagekit_focus(:north_east), do: "top_right"
  defp imagekit_focus(:north_west), do: "top_left"
  defp imagekit_focus(:south_east), do: "bottom_right"
  defp imagekit_focus(:south_west), do: "bottom_left"
  defp imagekit_focus({:xy, _, _}), do: "custom"
  defp imagekit_focus(_), do: nil

  defp imagekit_format(nil), do: []

  defp imagekit_format(%Ops.Format{} = f) do
    []
    |> ik_opt_unless_default("f", imagekit_format_atom(f.type), "auto")
    |> ik_opt_unless_default("q", f.quality, 80)
  end

  defp imagekit_format_atom(:auto), do: "auto"
  defp imagekit_format_atom(:jpeg), do: "jpg"
  defp imagekit_format_atom(:png), do: "png"
  defp imagekit_format_atom(:webp), do: "webp"
  defp imagekit_format_atom(:avif), do: "avif"
  defp imagekit_format_atom(_), do: nil

  defp imagekit_blur_sharpen(pipeline) do
    blur =
      case find_op(pipeline, Ops.Blur) do
        %Ops.Blur{sigma: s} when s > 0 -> ["e-blur-#{round(s * 100)}"]
        _ -> []
      end

    sharpen =
      case find_op(pipeline, Ops.Sharpen) do
        %Ops.Sharpen{sigma: s} when s > 0 -> ["e-sharpen-#{round(s * 10)}"]
        _ -> []
      end

    blur ++ sharpen
  end

  defp imagekit_rotate(nil), do: []
  defp imagekit_rotate(%Ops.Rotate{angle: 0}), do: []
  defp imagekit_rotate(%Ops.Rotate{angle: a}), do: ["rt-#{a}"]

  defp imagekit_background(nil), do: []
  defp imagekit_background(%Ops.Background{color: c}), do: ["bg-#{c}"]

  defp ik_opt(acc, _key, nil), do: acc
  defp ik_opt(acc, key, value), do: acc ++ ["#{key}-#{value}"]

  defp ik_opt_unless_default(acc, _key, value, default) when value == default, do: acc
  defp ik_opt_unless_default(acc, key, value, _default), do: ik_opt(acc, key, value)

  # ─── IIIF Image API 3.0 projection ───────────────────────────────
  #
  # IIIF URL grammar is positional, not key=value:
  #
  #   {host}{prefix}/{identifier}/{region}/{size}/{rotation}/{quality}.{format}
  #
  # The five segments are always emitted (the spec requires it).
  # Where the IR has no equivalent for a IIIF concept, we emit the
  # spec's "no-op" sentinel: `full` for region, `max` for size,
  # `0` for rotation, `default` for quality.

  # Identifier — strip leading `/`, percent-encode any embedded
  # `/` (so `subdir/cat.jpg` becomes `subdir%2Fcat.jpg`). Other
  # reserved chars left to URI.encode.
  defp iiif_encode_identifier(path) do
    path
    |> URI.encode(&URI.char_unreserved?/1)
  end

  # Region — `Ops.Crop` projects to the IIIF region segment.
  # When absent, defaults to `full`. The :cover-fit collision
  # documented in the moduledoc is NOT auto-mapped to `square`
  # (decision: drop).
  defp iiif_region(nil), do: "full"

  defp iiif_region(%{__struct__: mod, x: x, y: y, width: w, height: h, units: units})
       when mod == Ops.Crop do
    case units do
      :percent -> "pct:#{format_iiif_num(x)},#{format_iiif_num(y)},#{format_iiif_num(w)},#{format_iiif_num(h)}"
      _ -> "#{x},#{y},#{w},#{h}"
    end
  end

  # Defensive — absorb a Crop op even if `Ops.Crop` is not yet
  # defined in image_plug. Lets Phase 1 ship before Phase 2 lands
  # the IR addition; it just always produces `full`.
  defp iiif_region(_), do: "full"

  # Size — Resize maps onto the size segment with the spec's
  # comma syntax. Upscale prefix `^` (3.0 only) is emitted when
  # `Resize.upscale?` is true.
  defp iiif_size(nil), do: "max"

  defp iiif_size(%Ops.Resize{} = r) do
    upscale_prefix = if Map.get(r, :upscale?, true), do: "^", else: ""
    body = iiif_size_body(r)
    "#{upscale_prefix}#{body}"
  end

  defp iiif_size_body(%Ops.Resize{width: nil, height: nil} = r) do
    case Map.get(r, :size_pct) do
      nil -> "max"
      0 -> "max"
      pct when is_number(pct) and pct > 0 -> "pct:#{format_iiif_num(pct)}"
      _ -> "max"
    end
  end

  defp iiif_size_body(%Ops.Resize{width: w, height: nil}), do: "#{w},"
  defp iiif_size_body(%Ops.Resize{width: nil, height: h}), do: ",#{h}"

  defp iiif_size_body(%Ops.Resize{width: w, height: h, fit: :contain}), do: "!#{w},#{h}"
  defp iiif_size_body(%Ops.Resize{width: w, height: h, fit: :squeeze}), do: "#{w},#{h}"
  # `:cover` and `:crop` cannot be expressed in IIIF without an explicit
  # Crop op alongside. Document the gap by emitting the closest exact
  # form (`w,h` — distorts) but the conformance guide warns against it.
  defp iiif_size_body(%Ops.Resize{width: w, height: h}), do: "#{w},#{h}"

  # Rotation — IIIF 3.0 accepts any 0..360 angle plus an optional
  # leading `!` for mirror-then-rotate. We don't currently emit
  # the mirror form (no IR for it).
  defp iiif_rotation(nil), do: "0"
  defp iiif_rotation(%Ops.Rotate{angle: a}) when is_number(a), do: format_iiif_num(a)
  defp iiif_rotation(_), do: "0"

  # Quality — IIIF defines `default | color | gray | bitonal`.
  # We map saturation=0 to `gray` and Posterize{levels: 2} to
  # `bitonal`; everything else is `default`.
  defp iiif_quality(pipeline) do
    cond do
      iiif_grayscale?(pipeline) -> "gray"
      iiif_bitonal?(pipeline) -> "bitonal"
      true -> "default"
    end
  end

  defp iiif_grayscale?(pipeline) do
    case find_op(pipeline, Ops.Adjust) do
      %Ops.Adjust{saturation: s} when s == +0.0 -> true
      _ -> false
    end
  end

  defp iiif_bitonal?(pipeline) do
    case find_op(pipeline, Ops.Posterize) do
      %{levels: 2} -> true
      _ -> false
    end
  end

  # Format — IIIF requires a literal extension. `:auto` falls
  # back to the configured `:iiif_format` default (jpg).
  defp iiif_format_extension(nil, default), do: iiif_format_atom(default)
  defp iiif_format_extension(%Ops.Format{type: :auto}, default), do: iiif_format_atom(default)
  defp iiif_format_extension(%Ops.Format{type: type}, _default), do: iiif_format_atom(type)

  defp iiif_format_atom(:jpeg), do: "jpg"
  defp iiif_format_atom(:png), do: "png"
  defp iiif_format_atom(:gif), do: "gif"
  defp iiif_format_atom(:webp), do: "webp"
  defp iiif_format_atom(:tiff), do: "tif"
  defp iiif_format_atom(:jp2), do: "jp2"
  defp iiif_format_atom(:pdf), do: "pdf"
  defp iiif_format_atom(_), do: "jpg"

  # IIIF numbers — integers as integers, floats compactly. The
  # spec doesn't mandate trailing-zero stripping but cleaner URLs.
  defp format_iiif_num(n) when is_integer(n), do: Integer.to_string(n)

  defp format_iiif_num(n) when is_float(n) do
    if n == trunc(n),
      do: Integer.to_string(trunc(n)),
      else: :erlang.float_to_binary(n, [:compact, decimals: 4])
  end
end
