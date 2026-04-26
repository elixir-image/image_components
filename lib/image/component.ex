defmodule Image.Component do
  @moduledoc """
  Phoenix LiveView responsive-image component.

  Builds best-practice `<img srcset>` and `<picture>` markup against
  any image-CDN that speaks the [Cloudflare Images URL grammar](https://developers.cloudflare.com/images/transform-images/transform-via-url/),
  including [`image_plug`](https://hex.pm/packages/image_plug),
  Cloudflare itself, and custom Workers deployments.

  ### Components

  * `image/1` — emits a single `<img srcset sizes>` (or a
    `<picture>` with format-fallback `<source type=...>` entries
    when `:formats` is non-empty). The default for content images,
    heroes, and avatars.

  * `Image.Component.Picture.picture/1` — emits a `<picture>` with
    art-direction `<source media=...>` entries. Use when the crop
    or aspect ratio differs by breakpoint.

  ### Example

      <.image
        src="/photos/sunset.jpg"
        sizes="(min-width: 1200px) 800px, (min-width: 768px) 50vw, 100vw"
        formats={[:avif, :webp]}
        alt="Sunset over the harbour"
        width={1600}
        height={900}
        layout={:constrained}
        priority={:lcp}
      />

  ### Layout modes

  Mirrors [`@unpic/core`](https://github.com/ascorbic/unpic-img)'s
  three layout modes:

  * `:constrained` (default) — image scales down with its container
    but never up. Width-descriptor srcset capped at the intrinsic
    width. Sets `max-width`, `width: 100%`, `aspect-ratio` to
    prevent CLS.

  * `:fixed` — image renders at a single intrinsic size regardless
    of viewport. Density-descriptor srcset (`1x`, `2x`, `3x`). Use
    for logos, fixed-size avatars, icons.

  * `:full_width` — image always fills the viewport. Width-
    descriptor srcset over the full ladder. Sets `width: 100%;
    height: auto`.

  ### Performance attributes

  * Always sets `width` / `height` for CLS prevention.

  * `decoding="async"` always.

  * `priority: :lcp` shorthand for `loading="eager"
    fetchpriority="high"`. Otherwise `:loading` defaults to `:lazy`.

  ### Cross-host CDN

  Pass `:host` to point at a different deployment than the one
  rendering the LiveView (e.g. an image-plug deployment on a
  separate subdomain). Mirrors `unpic`'s `domain` option.
  """

  use Phoenix.Component

  alias Image.Component.{CDN, Layout, Srcset}

  attr :src, :string, required: true, doc: "Source path or absolute URL."
  attr :alt, :string, required: true, doc: "Alt text. Pass `\"\"` for purely decorative images."

  attr :sizes, :string,
    default: nil,
    doc:
      "The `sizes` attribute. Required for width-descriptor srcsets " <>
        "(`:constrained` and `:full_width` layouts); ignored for `:fixed`. " <>
        "If unset on a width-descriptor layout the component falls back to " <>
        "`100vw`."

  attr :width, :integer,
    default: nil,
    doc:
      "Intrinsic display width in CSS pixels. Required for `:fixed` and " <>
        "`:constrained` layouts."

  attr :height, :integer,
    default: nil,
    doc: "Intrinsic display height in CSS pixels. Strongly recommended for CLS prevention."

  attr :layout, :atom,
    default: :constrained,
    values: [:fixed, :constrained, :full_width],
    doc: "Layout mode. See moduledoc."

  attr :widths, :list,
    default: nil,
    doc: "Override the layout's default width ladder. Rarely needed."

  attr :max_width, :integer,
    default: nil,
    doc: "Cap the width ladder at this value. Drops widths > this from the output."

  attr :formats, :list,
    default: [],
    doc:
      "Format atoms (`:avif`, `:webp`) to emit as `<picture>` " <>
        "`<source type=...>` entries. Empty list = bare `<img>`."

  attr :loading, :atom,
    default: :lazy,
    values: [:lazy, :eager, :auto],
    doc: "`loading` attribute. Overridden to `:eager` when `priority: :lcp`."

  attr :priority, :atom,
    default: :normal,
    values: [:normal, :lcp],
    doc: "`:lcp` promotes the image to `loading=eager fetchpriority=high`."

  attr :host, :string,
    default: nil,
    doc:
      "Origin to prefix all generated URLs with. Mirrors unpic's `domain`. " <>
        "Defaults to root-relative URLs."

  attr :scheme, :string,
    default: nil,
    doc:
      "Scheme to use when `:host` is a bare hostname. Defaults to `\"https\"`. " <>
        "Falls back to `Application.get_env(:image_components, :defaults)[:scheme]` " <>
        "when not set."

  attr :mount, :string,
    default: "",
    doc: "Path prefix the receiving image plug is mounted under."

  attr :url_options, :list,
    default: [],
    doc:
      "Extra CDN options (e.g. `[fit: :cover, quality: 80]`) applied to " <>
        "every URL in the srcset. Keys are CDN-specific; the default " <>
        "Cloudflare adapter accepts every key documented in `Image.Component.URL`."

  attr :cdn, :any,
    default: nil,
    doc:
      "CDN adapter selection. Atom shorthand (`:cloudflare`), module " <>
        "name, or `{module, opts}` tuple. Defaults to `:cloudflare`. " <>
        "Falls back to `Application.get_env(:image_components, :defaults)[:cdn]`. " <>
        "See `Image.Component.CDN` for adding custom adapters."

  attr :signing_keys, :list,
    default: nil,
    doc:
      "When set, every emitted URL is HMAC-signed via " <>
        "`Image.Component.Signing.sign/3`. The first key is used; " <>
        "the back-end's `Image.Plug` `:signing` configuration must " <>
        "include the same key for verification to pass."

  attr :signing_expires_at, :any,
    default: nil,
    doc:
      "`DateTime` or unix-seconds; only consulted when `:signing_keys` is " <>
        "set. Adds an `?exp=<unix-seconds>` parameter that the back-end " <>
        "verifier rejects after the given time."

  attr :rest, :global, doc: "Any additional HTML attributes on the `<img>`."

  @doc """
  Renders an `<img>` or `<picture>` element with a responsive
  srcset, sensible defaults, and CLS-preventing layout CSS.
  """
  def image(assigns) do
    assigns = compute_assigns(assigns)

    if assigns.formats == [] do
      ~H"""
      <img
        src={@src_url}
        srcset={@srcset}
        sizes={@resolved_sizes}
        alt={@alt}
        width={@width}
        height={@height}
        loading={@resolved_loading}
        decoding="async"
        fetchpriority={@fetchpriority}
        style={@style}
        {@rest}
      />
      """
    else
      ~H"""
      <picture>
        <source
          :for={{format, srcset} <- @per_format_srcsets}
          type={Srcset.mime_type(format)}
          srcset={srcset}
          sizes={@resolved_sizes}
        />
        <img
          src={@src_url}
          srcset={@srcset}
          sizes={@resolved_sizes}
          alt={@alt}
          width={@width}
          height={@height}
          loading={@resolved_loading}
          decoding="async"
          fetchpriority={@fetchpriority}
          style={@style}
          {@rest}
        />
      </picture>
      """
    end
  end

  @doc false
  # Public for use by `Image.Component.Picture`.
  def compute_assigns(assigns) do
    layout =
      Layout.compute(assigns.layout, assigns.width, assigns.height,
        widths: assigns.widths,
        max_width: assigns.max_width
      )

    defaults = Application.get_env(:image_components, :defaults, [])
    {cdn_module, _cdn_opts} = cdn = CDN.resolve(assigns.cdn || Keyword.get(defaults, :cdn))

    url_options =
      Keyword.get(defaults, :url_options, [])
      |> Keyword.merge(assigns.url_options)
      |> Keyword.put_new(:mount, resolve_mount(assigns.mount, defaults))
      |> maybe_put(:host, assigns.host || Keyword.get(defaults, :host))
      |> maybe_put(:scheme, assigns.scheme || Keyword.get(defaults, :scheme) || "https")
      |> maybe_put(:signing_keys, assigns.signing_keys || Keyword.get(defaults, :signing_keys))
      |> maybe_put(
        :signing_expires_at,
        assigns.signing_expires_at || Keyword.get(defaults, :signing_expires_at)
      )

    srcset = Srcset.build(assigns.src, layout, url_options: url_options, cdn: cdn)

    per_format_srcsets =
      Srcset.per_format(assigns.src, layout,
        url_options: url_options,
        formats: assigns.formats,
        cdn: cdn
      )

    src_url =
      cdn_module.build_url(assigns.src, Keyword.put(url_options, :width, src_url_width(layout)))

    {resolved_loading, fetchpriority} =
      case assigns.priority do
        :lcp -> {"eager", "high"}
        _ -> {Atom.to_string(assigns.loading), nil}
      end

    resolved_sizes = resolve_sizes(layout.srcset_kind, assigns.sizes)

    assigns
    |> assign(:layout_data, layout)
    |> assign(:srcset, srcset)
    |> assign(:per_format_srcsets, per_format_srcsets)
    |> assign(:src_url, src_url)
    |> assign(:resolved_loading, resolved_loading)
    |> assign(:fetchpriority, fetchpriority)
    |> assign(:resolved_sizes, resolved_sizes)
    |> assign(:style, layout.style)
  end

  defp src_url_width(%{widths: widths}), do: Enum.max(widths)

  defp resolve_sizes(:density, _sizes), do: nil
  defp resolve_sizes(:width, nil), do: "100vw"
  defp resolve_sizes(:width, sizes) when is_binary(sizes), do: sizes

  defp maybe_put(keyword, _key, nil), do: keyword

  defp maybe_put(keyword, key, value) do
    Keyword.put(keyword, key, value)
  end

  # If the assign is the default empty string, fall back to the
  # configured default; otherwise honour the per-call value.
  defp resolve_mount("", defaults), do: Keyword.get(defaults, :mount, "")
  defp resolve_mount(value, _defaults) when is_binary(value), do: value
end
