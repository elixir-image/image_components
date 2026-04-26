defmodule Image.Component.Srcset do
  @moduledoc """
  `srcset`-string generation for the responsive-image component.

  Two flavours of srcset, driven by `Image.Component.Layout`:

  * **Width descriptors** (`url 320w, url 800w, ...`) — used when
    the rendered CSS width depends on the viewport. Combined with a
    `sizes` attribute the browser picks the smallest source that
    satisfies `sizes × DPR`. The right choice for `:constrained`
    and `:full_width` layouts.

  * **Density descriptors** (`url 1x, url@2x 2x, url@3x 3x`) —
    used when the rendered CSS width is fixed regardless of the
    viewport. The browser only selects on DPR. The right choice
    for `:fixed` layouts (logos, avatars).

  Per the WHATWG spec the two cannot be mixed in one `srcset`.
  This module's `build/2` chooses the right form based on the
  layout's `:srcset_kind`.
  """


  @doc """
  Builds a `srcset` attribute value for the given source and layout.

  ### Arguments

  * `source` — the source path or absolute URL passed to
    `Image.Component.URL.build/2`.

  * `layout` — a `t:Image.Component.Layout.t/0` map. Its
    `:srcset_kind` and `:widths` drive the output shape.

  ### Options

  * `:url_options` — keyword list passed verbatim to the CDN's
    `build_url/2` for every entry. Per-entry `:width` (or `:dpr`)
    is injected automatically and overrides any value in
    `:url_options`.

  * `:cdn` — `{module, opts}` tuple identifying the CDN adapter
    (see `Image.Component.CDN`). Defaults to
    `{Image.Component.CDN.Cloudflare, []}`.

  ### Returns

  * The `srcset`-attribute string.

  """
  @spec build(String.t(), Image.Component.Layout.t(), keyword()) :: String.t()
  def build(source, layout, options \\ []) when is_binary(source) and is_map(layout) do
    url_options = Keyword.get(options, :url_options, [])
    {cdn_module, _cdn_opts} = Keyword.get(options, :cdn, {Image.Component.CDN.Cloudflare, []})

    case layout.srcset_kind do
      :width -> build_width(source, layout.widths, url_options, cdn_module)
      :density -> build_density(source, layout.widths, url_options, cdn_module)
    end
  end

  defp build_width(source, widths, url_options, cdn_module) do
    widths
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn width ->
      url = cdn_module.build_url(source, Keyword.put(url_options, :width, width))
      "#{url} #{width}w"
    end)
    |> Enum.join(", ")
  end

  defp build_density(source, widths, url_options, cdn_module) do
    # `widths` for the density form is a sorted list of pixel
    # widths, one per DPR factor (e.g. [200, 400, 600] for a
    # base-200 fixed image at 1x/2x/3x). The factor is the index
    # plus one (1x is the first entry).
    widths
    |> Enum.with_index(1)
    |> Enum.map(fn {width, factor} ->
      url = cdn_module.build_url(source, Keyword.put(url_options, :width, width))
      "#{url} #{factor}x"
    end)
    |> Enum.join(", ")
  end

  @doc """
  Builds a per-format keyword list of srcsets for `<picture>`'s
  `<source type=...>` entries.

  ### Arguments

  * `source` — the source path or URL.

  * `layout` — a `t:Image.Component.Layout.t/0`.

  * `options` is a keyword list. Same keys as `build/3` plus:

  ### Options

  * `:formats` — list of format atoms in priority order
    (most-modern first). Defaults to `[:avif, :webp]`. The base
    `<img>`'s own format (typically `:auto`) is the caller's
    responsibility and is not included.

  ### Returns

  * A keyword list `[{format, srcset}]` preserving the order of
    `:formats`.

  """
  @spec per_format(String.t(), Image.Component.Layout.t(), keyword()) :: [{atom(), String.t()}]
  def per_format(source, layout, options \\ []) when is_binary(source) and is_map(layout) do
    formats = Keyword.get(options, :formats, [:avif, :webp])
    base_url_options = Keyword.get(options, :url_options, [])
    cdn = Keyword.get(options, :cdn, {Image.Component.CDN.Cloudflare, []})

    Enum.map(formats, fn format ->
      url_options = Keyword.put(base_url_options, :format, format)
      {format, build(source, layout, url_options: url_options, cdn: cdn)}
    end)
  end

  @doc """
  Maps a format atom to the corresponding `<source type=...>` MIME
  type.

  ### Examples

      iex> Image.Component.Srcset.mime_type(:avif)
      "image/avif"

      iex> Image.Component.Srcset.mime_type(:webp)
      "image/webp"

      iex> Image.Component.Srcset.mime_type(:jpeg)
      "image/jpeg"

  """
  @spec mime_type(atom()) :: String.t()
  def mime_type(:avif), do: "image/avif"
  def mime_type(:webp), do: "image/webp"
  def mime_type(:jpeg), do: "image/jpeg"
  def mime_type(:baseline_jpeg), do: "image/jpeg"
  def mime_type(:png), do: "image/png"
  def mime_type(:gif), do: "image/gif"
  def mime_type(other) when is_atom(other), do: "image/#{other}"
end
