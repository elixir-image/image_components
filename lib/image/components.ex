defmodule Image.Components do
  @moduledoc """
  Phoenix.Component wrappers for the `image` / `image_plug`
  ecosystem.

  Exposes two LiveView-friendly components — `<.image>` and
  `<.picture>` — that take per-transform attributes (width,
  height, fit, format, blur, brightness, …), build a canonical
  `Image.Plug.Pipeline`, and project that pipeline onto the URL
  grammar of one of five supported providers via
  `Image.Components.URL`: four commercial image CDNs (Cloudflare
  Images, Cloudinary, imgix, ImageKit) plus
  [IIIF Image API 3.0](https://iiif.io/api/image/3.0/).

  Use this module like any other Phoenix.Component:

      defmodule MyAppWeb.PageLive do
        use MyAppWeb, :live_view
        import Image.Components

        def render(assigns) do
          ~H\"\"\"
          <.image src="/uploads/cat.jpg" provider={:cloudflare} width={600} fit={:cover} />
          \"\"\"
        end
      end

  Each component renders a plain HTML element (`<img>` or
  `<picture>`); the only "magic" is constructing the URL. There
  is no JavaScript and no LiveView-specific behavior.

  ## Provider feature gaps

  Not every transform is expressible in every CDN's URL grammar.
  Operations that don't have a faithful equivalent are silently
  dropped from the URL projection — see
  `Image.Components.URL` for the per-provider coverage table.

  """

  use Phoenix.Component

  alias Image.Plug.Pipeline
  alias Image.Plug.Pipeline.Ops
  alias Image.Components.URL

  @providers ~w(cloudflare cloudinary imgix imagekit iiif)a

  @doc """
  Renders an `<img>` whose `src` is built by projecting the
  attribute set onto the configured CDN provider's URL grammar.

  ### Attributes

  * `src` — the canonical, *untransformed* source path or URL
    (e.g. `/uploads/cat.jpg`). Required.

  * `provider` — `:cloudflare`, `:cloudinary`, `:imgix`, or
    `:imagekit`. Required.

  * `host` — optional URL prefix (e.g. `"https://cdn.example.com"`
    or `"/img"`). Defaults to `""` (relative URL).

  * `width`, `height` — pixel dimensions. Optional.

  * `fit` — one of `:contain`, `:cover`, `:crop`, `:pad`,
    `:scale_down`, `:squeeze`. Optional.

  * `gravity` — `:center`, `:auto`, `:face`, `:north`, `:south`,
    `:east`, `:west`, `:north_east`, `:north_west`,
    `:south_east`, `:south_west`, or `{:xy, x, y}`. Optional.

  * `dpr` — device-pixel-ratio multiplier. Optional.

  * `face_zoom` — float in `[0.0, 1.0]` controlling how tightly a face-aware crop hugs the detected face. `0.0` is a loose crop with lots of context, `1.0` hugs the bounding box. Only meaningful with `gravity={:face}`. Optional.

  * `format` — `:auto`, `:jpeg`, `:png`, `:webp`, `:avif`. Optional.

  * `quality` — `1..100`. Optional.

  * `blur`, `sharpen` — sigma (float ≥ 0). Optional.

  * `brightness`, `contrast`, `saturation`, `gamma` — multipliers where `1.0` means no change. Optional.

  * `vignette` — strength in `[0.0, 1.0]`. Only Cloudinary's URL grammar carries vignette; other providers drop it. Optional.

  * `tint` — colour as a hex string (`"#aabbcc"` or `"aabbcc"`) or an `[r, g, b]` integer list. Only imgix's `monochrome=` carries this; other providers drop it. Optional.

  * `cloudinary_account` — the Cloudinary `<cloud-name>` segment. Defaults to `"demo"`.

  * `imagekit_endpoint` — the ImageKit per-account endpoint segment. Defaults to `"demo"`.

  * `class`, `alt`, plus any other arbitrary HTML attributes — passed through to the rendered `<img>` via `:rest`.

  ### Returns

  * Renders a single `<img>` element.

  ### Examples

      <.image src="/cat.jpg" provider={:cloudflare} width={600} fit={:cover} />

      <.image
        src="/cat.jpg"
        provider={:imgix}
        host="https://my-source.imgix.net"
        width={800}
        format={:webp}
        quality={80}
        blur={5.0}
      />

  """
  attr(:src, :string, required: true)
  attr(:provider, :atom, values: @providers, required: true)
  attr(:host, :string, default: "")
  attr(:width, :integer, default: nil)
  attr(:height, :integer, default: nil)
  attr(:fit, :atom, default: nil)
  attr(:gravity, :any, default: nil)
  attr(:dpr, :integer, default: nil)
  attr(:face_zoom, :float, default: nil)
  attr(:format, :atom, default: nil)
  attr(:quality, :integer, default: nil)
  attr(:blur, :float, default: nil)
  attr(:sharpen, :float, default: nil)
  attr(:brightness, :float, default: nil)
  attr(:contrast, :float, default: nil)
  attr(:saturation, :float, default: nil)
  attr(:gamma, :float, default: nil)
  attr(:vignette, :float, default: nil)
  attr(:tint, :any, default: nil)
  # IIIF-specific. `:region` defines a sub-rectangle of the source
  # image (`:full`, `{:pixels, x, y, w, h}`, or `{:percent, x, y, w, h}`).
  # `:iiif_quality` is one of `:default`, `:color`, `:gray`,
  # `:bitonal` per the IIIF spec — distinct from `:quality` (which
  # is the compression quality `1..100`). Both are honoured by the
  # `:iiif` provider; other providers ignore them.
  attr(:region, :any, default: nil)
  attr(:iiif_quality, :atom, values: [:default, :color, :gray, :bitonal, nil], default: nil)
  attr(:cloudinary_account, :string, default: "demo")
  attr(:imagekit_endpoint, :string, default: "demo")
  # IIIF server prefix segment; e.g. `"/iiif/3"` for an Image API
  # 3.0 server. Only used when `provider: :iiif`.
  attr(:iiif_prefix, :string, default: "/iiif/3")
  # Fallback format extension when `Format.type` is `:auto`. IIIF
  # requires an explicit format in the URL.
  attr(:iiif_format, :atom, default: :jpeg)
  attr(:rest, :global, include: ~w(alt class srcset sizes loading decoding fetchpriority))

  def image(assigns) do
    pipeline = build_pipeline(assigns)

    url =
      build_url(assigns.provider, pipeline,
        source_path: assigns.src,
        host: assigns.host,
        cloudinary_account: assigns.cloudinary_account,
        imagekit_endpoint: assigns.imagekit_endpoint,
        iiif_prefix: assigns[:iiif_prefix] || "/iiif/3",
        iiif_format: assigns[:iiif_format] || :jpeg
      )

    assigns = assign(assigns, :__src, url)

    ~H"""
    <img src={@__src} {@rest} />
    """
  end

  @doc """
  Renders a `<picture>` element with format-specific
  `<source srcset>` rows that share the rest of the transform
  set, plus a fallback `<img>`.

  ### Attributes

  Same as `image/1`, with one extra:

  * `formats` — list of formats to emit as `<source>` rows.
    Defaults to `[:avif, :webp]`. The fallback `<img>` uses
    `format` if given, otherwise the original format.

  ### Returns

  * Renders a `<picture>` element with one `<source>` per
    requested format and a single `<img>` fallback.

  ### Examples

      <.picture src="/cat.jpg" provider={:cloudflare} width={600} formats={[:avif, :webp]} />

  """
  attr(:src, :string, required: true)
  attr(:provider, :atom, values: @providers, required: true)
  attr(:host, :string, default: "")
  attr(:formats, :list, default: [:avif, :webp])
  attr(:width, :integer, default: nil)
  attr(:height, :integer, default: nil)
  attr(:fit, :atom, default: nil)
  attr(:gravity, :any, default: nil)
  attr(:dpr, :integer, default: nil)
  attr(:face_zoom, :float, default: nil)
  attr(:format, :atom, default: nil)
  attr(:quality, :integer, default: nil)
  attr(:blur, :float, default: nil)
  attr(:sharpen, :float, default: nil)
  attr(:brightness, :float, default: nil)
  attr(:contrast, :float, default: nil)
  attr(:saturation, :float, default: nil)
  attr(:gamma, :float, default: nil)
  attr(:vignette, :float, default: nil)
  attr(:tint, :any, default: nil)
  attr(:region, :any, default: nil)
  attr(:iiif_quality, :atom, values: [:default, :color, :gray, :bitonal, nil], default: nil)
  attr(:cloudinary_account, :string, default: "demo")
  attr(:imagekit_endpoint, :string, default: "demo")
  attr(:iiif_prefix, :string, default: "/iiif/3")
  attr(:iiif_format, :atom, default: :jpeg)
  attr(:rest, :global, include: ~w(alt class loading decoding fetchpriority))

  def picture(assigns) do
    base = Map.drop(assigns, [:formats, :rest])
    common_url_options = picture_url_options(assigns)

    sources =
      Enum.map(assigns.formats, fn fmt ->
        url =
          build_url(
            assigns.provider,
            build_pipeline(%{base | format: fmt}),
            common_url_options
          )

        %{format: fmt, url: url, mime: mime(fmt)}
      end)

    fallback_url =
      build_url(assigns.provider, build_pipeline(base), common_url_options)

    assigns = assign(assigns, sources: sources, fallback_url: fallback_url)

    ~H"""
    <picture>
      <source :for={s <- @sources} type={s.mime} srcset={s.url} />
      <img src={@fallback_url} {@rest} />
    </picture>
    """
  end

  # ─── shared internals ─────────────────────────────────────────────

  @doc false
  # Build the canonical IR from the component's flat attribute
  # set. Public-but-undocumented for the playground; not part of
  # the stable API.
  def build_pipeline(assigns) do
    resize_fields =
      [
        width: assigns[:width],
        height: assigns[:height],
        fit: assigns[:fit],
        gravity: assigns[:gravity],
        dpr: assigns[:dpr],
        face_zoom: assigns[:face_zoom]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    adjust_fields =
      [
        brightness: assigns[:brightness],
        contrast: assigns[:contrast],
        saturation: assigns[:saturation],
        gamma: assigns[:gamma]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    format_fields =
      [type: assigns[:format], quality: assigns[:quality]]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    ops =
      []
      |> maybe_prepend(resize_fields, fn fs -> struct(Ops.Resize, fs) end)
      |> maybe_prepend(adjust_fields, fn fs -> struct(Ops.Adjust, fs) end)
      |> maybe_prepend_blur(assigns[:blur])
      |> maybe_prepend_sharpen(assigns[:sharpen])
      |> maybe_prepend_vignette(assigns[:vignette])
      |> maybe_prepend_tint(assigns[:tint])
      |> maybe_apply_iiif_quality(assigns[:iiif_quality])
      |> maybe_prepend_region(assigns[:region])

    output =
      case format_fields do
        [] -> nil
        fs -> struct(Ops.Format, fs)
      end

    %Pipeline{ops: ops, output: output}
  end

  defp maybe_prepend(ops, [], _builder), do: ops
  defp maybe_prepend(ops, fields, builder), do: [builder.(fields) | ops]

  defp maybe_prepend_blur(ops, nil), do: ops
  defp maybe_prepend_blur(ops, sigma) when sigma > 0, do: [%Ops.Blur{sigma: sigma * 1.0} | ops]
  defp maybe_prepend_blur(ops, _), do: ops

  defp maybe_prepend_sharpen(ops, nil), do: ops

  defp maybe_prepend_sharpen(ops, sigma) when sigma > 0,
    do: [%Ops.Sharpen{sigma: sigma * 1.0} | ops]

  defp maybe_prepend_sharpen(ops, _), do: ops

  defp maybe_prepend_vignette(ops, nil), do: ops

  defp maybe_prepend_vignette(ops, strength) when strength > 0,
    do: [%Ops.Vignette{strength: strength * 1.0} | ops]

  defp maybe_prepend_vignette(ops, _), do: ops

  defp maybe_prepend_tint(ops, nil), do: ops

  defp maybe_prepend_tint(ops, color) do
    case normalise_color(color) do
      nil -> ops
      [_, _, _] = rgb -> [%Ops.Tint{color: rgb} | ops]
    end
  end

  # `Ops.Tint`'s type is `[non_neg_integer()]`. Accept the
  # convenience forms — hex string ("#aabbcc" or "aabbcc"),
  # already-an-RGB-list — and normalise to a 3-element int
  # list. Anything else is silently dropped.
  defp normalise_color([r, g, b]) when is_integer(r) and is_integer(g) and is_integer(b),
    do: [r, g, b]

  defp normalise_color("#" <> rest), do: normalise_color(rest)

  defp normalise_color(<<r::binary-2, g::binary-2, b::binary-2>>) do
    with {:ok, ri} <- parse_hex_byte(r),
         {:ok, gi} <- parse_hex_byte(g),
         {:ok, bi} <- parse_hex_byte(b) do
      [ri, gi, bi]
    else
      _ -> nil
    end
  end

  defp normalise_color(_), do: nil

  defp parse_hex_byte(<<_::binary-2>> = pair) do
    case Integer.parse(pair, 16) do
      {n, ""} when n in 0..255 -> {:ok, n}
      _ -> :error
    end
  end

  # IIIF quality — `:gray` ⇒ ensure an `Ops.Adjust{saturation: 0.0}`
  # is in the pipeline; `:bitonal` ⇒ ensure an `Ops.Posterize{levels:
  # 2}` is. `:default` / `:color` / `nil` are no-ops. Other
  # providers ignore the resulting ops if their URL grammar can't
  # carry them; for `:iiif`, this is what
  # `Image.Components.URL.iiif/2`'s quality detector reads.
  defp maybe_apply_iiif_quality(ops, nil), do: ops
  defp maybe_apply_iiif_quality(ops, :default), do: ops
  defp maybe_apply_iiif_quality(ops, :color), do: ops

  defp maybe_apply_iiif_quality(ops, :gray) do
    {existing_adjust, others} = pop_op(ops, Ops.Adjust)
    base = existing_adjust || %Ops.Adjust{}
    [%{base | saturation: 0.0} | others]
  end

  defp maybe_apply_iiif_quality(ops, :bitonal) do
    {_existing_posterize, others} = pop_op(ops, Ops.Posterize)
    [%Ops.Posterize{levels: 2} | others]
  end

  defp pop_op(ops, module) do
    {match, rest} = Enum.split_with(ops, fn o -> o.__struct__ == module end)
    {List.first(match), rest}
  end

  # IIIF region — `:full` (or nil) is a no-op. `{:pixels, x, y, w, h}`
  # / `{:percent, x, y, w, h}` build an `Ops.Crop` op, IF that
  # struct exists in the loaded `image_plug`. When `Ops.Crop` is
  # not yet defined (Phase 2a of the IIIF rollout) this silently
  # drops the region — `Image.Components.URL.iiif/2`'s `iiif_region/1`
  # then emits `full`.
  defp maybe_prepend_region(ops, nil), do: ops
  defp maybe_prepend_region(ops, :full), do: ops

  defp maybe_prepend_region(ops, {units, x, y, w, h}) when units in [:pixels, :percent] do
    if Code.ensure_loaded?(Ops.Crop) do
      [struct(Ops.Crop, x: x, y: y, width: w, height: h, units: units) | ops]
    else
      ops
    end
  end

  defp maybe_prepend_region(ops, _), do: ops

  defp picture_url_options(assigns) do
    [
      source_path: assigns.src,
      host: assigns.host,
      cloudinary_account: assigns.cloudinary_account,
      imagekit_endpoint: assigns.imagekit_endpoint,
      iiif_prefix: assigns[:iiif_prefix] || "/iiif/3",
      iiif_format: assigns[:iiif_format] || :jpeg
    ]
  end

  defp build_url(:cloudflare, pipeline, options), do: URL.cloudflare(pipeline, options)
  defp build_url(:cloudinary, pipeline, options), do: URL.cloudinary(pipeline, options)
  defp build_url(:imgix, pipeline, options), do: URL.imgix(pipeline, options)
  defp build_url(:imagekit, pipeline, options), do: URL.imagekit(pipeline, options)
  defp build_url(:iiif, pipeline, options), do: URL.iiif(pipeline, options)

  defp mime(:avif), do: "image/avif"
  defp mime(:webp), do: "image/webp"
  defp mime(:jpeg), do: "image/jpeg"
  defp mime(:png), do: "image/png"
  defp mime(_), do: nil
end
