defmodule Image.Component.Picture do
  @moduledoc """
  Art-direction `<picture>` component.

  Use this when the *crop or aspect ratio* should change at
  different breakpoints (true art direction), not just the
  resolution. For format negotiation alone (AVIF → WebP → JPEG),
  use `Image.Component.image/1` with the `:formats` attr — that
  emits a simpler `<picture>` with only `<source type=...>` entries.

  ### Example

      <.picture
        alt="Portrait of the company founder"
        sources={[
          %{
            media: "(min-width: 1024px)",
            src: "/founder.jpg",
            url_options: [fit: :cover, gravity: :face],
            width: 1200,
            height: 800,
            sizes: "1200px"
          },
          %{
            media: "(min-width: 480px)",
            src: "/founder.jpg",
            url_options: [fit: :cover, gravity: :face],
            width: 800,
            height: 1000,
            sizes: "100vw"
          }
        ]}
        fallback={%{
          src: "/founder.jpg",
          url_options: [fit: :cover, gravity: :face],
          width: 480,
          height: 600,
          sizes: "100vw"
        }}
      />

  Each entry in `:sources` and the single `:fallback` accepts the
  same shape as `Image.Component.image/1`'s attrs (as a map),
  except art-direction-specific keys:

  * `:media` (`<source>` only) — the CSS media query under which
    this source applies. The first matching `<source>` wins; the
    `<img>` inside provides the `:fallback` for when no media
    query matches.

  Each source's `:formats` produces multiple `<source type=...>`
  entries under the same `:media` (browsers walk them in order
  and pick the first supported `type`).
  """

  use Phoenix.Component

  alias Image.Component.{CDN, Layout, Srcset}

  attr :alt, :string, required: true, doc: "Alt text on the fallback `<img>`."

  attr :sources, :list,
    required: true,
    doc:
      "List of source maps, each with `:media` plus the same keys " <>
        "as `Image.Component.image/1`'s attrs. The first source whose " <>
        "media query matches wins."

  attr :fallback, :map,
    required: true,
    doc:
      "The fallback `<img>` source. Same key shape as a `:sources` " <>
        "entry but without `:media`."

  attr :loading, :atom, default: :lazy, values: [:lazy, :eager, :auto]
  attr :priority, :atom, default: :normal, values: [:normal, :lcp]
  attr :host, :string, default: nil
  attr :scheme, :string, default: "https"
  attr :mount, :string, default: ""
  attr :cdn, :any, default: nil, doc: "CDN adapter (atom, module, or `{module, opts}` tuple). See `Image.Component.CDN`."

  attr :rest, :global

  @doc """
  Renders an art-direction `<picture>` element.
  """
  def picture(assigns) do
    {resolved_loading, fetchpriority} =
      case assigns.priority do
        :lcp -> {"eager", "high"}
        _ -> {Atom.to_string(assigns.loading), nil}
      end

    fallback = build_fallback(assigns.fallback, assigns)
    sources = Enum.map(assigns.sources, &build_source(&1, assigns))

    assigns =
      assigns
      |> assign(:resolved_loading, resolved_loading)
      |> assign(:fetchpriority, fetchpriority)
      |> assign(:sources_data, sources)
      |> assign(:fallback_data, fallback)

    ~H"""
    <picture>
      <%= for source <- @sources_data, entry <- source.entries do %>
        <source
          media={source.media}
          type={entry.type}
          srcset={entry.srcset}
          sizes={source.sizes}
        />
      <% end %>
      <img
        src={@fallback_data.src_url}
        srcset={@fallback_data.srcset}
        sizes={@fallback_data.sizes}
        alt={@alt}
        width={@fallback_data.width}
        height={@fallback_data.height}
        loading={@resolved_loading}
        decoding="async"
        fetchpriority={@fetchpriority}
        style={@fallback_data.style}
        {@rest}
      />
    </picture>
    """
  end

  defp build_source(source, assigns) do
    common = url_options(source, assigns)
    cdn = resolve_cdn(assigns)
    layout = layout_for(source)
    formats = Map.get(source, :formats, [:avif, :webp])

    entries =
      Enum.map(formats, fn format ->
        url_options = Keyword.put(common, :format, format)

        %{
          type: Srcset.mime_type(format),
          srcset: Srcset.build(source.src, layout, url_options: url_options, cdn: cdn)
        }
      end)

    %{
      media: source.media,
      sizes: resolve_sizes(layout.srcset_kind, Map.get(source, :sizes)),
      entries: entries
    }
  end

  defp build_fallback(fallback, assigns) do
    common = url_options(fallback, assigns)
    {cdn_module, _} = cdn = resolve_cdn(assigns)
    layout = layout_for(fallback)

    %{
      src_url:
        cdn_module.build_url(fallback.src, Keyword.put(common, :width, Enum.max(layout.widths))),
      srcset: Srcset.build(fallback.src, layout, url_options: common, cdn: cdn),
      sizes: resolve_sizes(layout.srcset_kind, Map.get(fallback, :sizes)),
      width: fallback.width,
      height: Map.get(fallback, :height),
      style: layout.style
    }
  end

  defp layout_for(source) do
    Layout.compute(
      Map.get(source, :layout, :constrained),
      Map.get(source, :width),
      Map.get(source, :height),
      widths: Map.get(source, :widths),
      max_width: Map.get(source, :max_width)
    )
  end

  defp url_options(source, assigns) do
    defaults = Application.get_env(:image_components, :defaults, [])

    Keyword.get(defaults, :url_options, [])
    |> Keyword.merge(Map.get(source, :url_options, []))
    |> Keyword.put_new(:mount, resolve_mount(assigns.mount, defaults))
    |> maybe_put(:host, assigns.host || Keyword.get(defaults, :host))
    |> maybe_put(:scheme, assigns.scheme || Keyword.get(defaults, :scheme) || "https")
    |> maybe_put(
      :signing_keys,
      Map.get(source, :signing_keys) || Keyword.get(defaults, :signing_keys)
    )
    |> maybe_put(
      :signing_expires_at,
      Map.get(source, :signing_expires_at) || Keyword.get(defaults, :signing_expires_at)
    )
  end

  defp resolve_mount("", defaults), do: Keyword.get(defaults, :mount, "")
  defp resolve_mount(value, _defaults) when is_binary(value), do: value

  defp resolve_cdn(assigns) do
    defaults = Application.get_env(:image_components, :defaults, [])
    CDN.resolve(assigns[:cdn] || Map.get(assigns, :cdn) || Keyword.get(defaults, :cdn))
  end

  defp resolve_sizes(:density, _sizes), do: nil
  defp resolve_sizes(:width, nil), do: "100vw"
  defp resolve_sizes(:width, sizes) when is_binary(sizes), do: sizes

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)
end
