defmodule Image.Components.IIIF do
  @moduledoc """
  IIIF Image API 3.0-specific Phoenix components.

  `<.image provider={:iiif}>` covers the static-thumbnail case —
  it emits a single `<img>` whose `src` is built by
  `Image.Components.URL.iiif/2`. This module covers the IIIF
  fundamentals that don't fit the cross-provider component shape:

    * **`:static` mode** — same as `<.image provider={:iiif}>`,
      but lives here for symmetry with the other modes. Renders a
      single `<img>`.

    * **`:tiles` mode** — emits a CSS grid of `<img>` tiles at a
      chosen scale factor. No JavaScript. Useful for high-resolution
      static layouts (atlases, scanned documents) where the tile
      structure of the IIIF source maps cleanly onto a fixed-size
      grid.

    * **`:viewer` mode** — emits a `<div>` carrying
      `data-iiif-info-url=…`, ready for a JavaScript deep-zoom
      viewer (OpenSeadragon, Mirador, Leaflet-IIIF) to mount into.
      A static fallback `<img>` lives inside the div for the
      no-JS / loading-state case.

  Use this module when your image source is IIIF-compliant *and*
  you need tiling or viewer mounting. For thumbnails, use the
  generic `<.image provider={:iiif}>` from `Image.Components`.

  ## Usage

      defmodule MyAppWeb.GalleryLive do
        use MyAppWeb, :live_view
        import Image.Components.IIIF

        def render(assigns) do
          ~H\"\"\"
          <%!-- Static thumbnail --%>
          <.iiif src="/cat.jpg" host="https://iiif.example.org" width={400} />

          <%!-- Tile grid for a 4096×4096 source at scale factor 2 --%>
          <.iiif
            src="/atlas.jpg"
            host="https://iiif.example.org"
            mode={:tiles}
            source_width={4096}
            source_height={4096}
            tile_width={512}
            scale_factor={2}
          />

          <%!-- Deep-zoom viewer mount --%>
          <.iiif
            src="/portrait.jpg"
            host="https://iiif.example.org"
            mode={:viewer}
            width={800}
            height={600}
            phx-hook="OpenSeadragon"
            id="viewer-1"
          />
          \"\"\"
        end
      end

  See [the IIIF guide](https://hexdocs.pm/image_components/iiif.html)
  for the per-mode walkthrough and the JavaScript-viewer wiring
  recipe.
  """

  use Phoenix.Component

  alias Image.Components.URL
  alias Image.Plug.Pipeline
  alias Image.Plug.Pipeline.Ops

  @doc """
  Renders an IIIF image. See the moduledoc for mode descriptions.

  ### Attributes

  Common to all modes:

  * `src` — the IIIF identifier path. Required.

  * `host` — the IIIF server's host (e.g. `\"https://iiif.example.org\"`).
    Defaults to `\"\"`.

  * `iiif_prefix` — the server's IIIF version prefix segment.
    Defaults to `\"/iiif/3\"`.

  * `mode` — `:static` (default), `:tiles`, or `:viewer`.

  Static mode uses every per-transform attribute that
  `Image.Components.image/1` accepts (`width`, `height`, `fit`,
  `region`, `iiif_quality`, `format`, …) — see that component's docs.

  Tile mode (`mode={:tiles}`):

  * `source_width`, `source_height` — the source image's pixel
    dimensions, *required*. (Discover them from `info.json` if you
    don't have them — the discovery step is out of scope here.)

  * `tile_width` — pixel width of each rendered tile. Defaults to
    `512` (the IIIF Image API 3.0 default tile size). Pass the
    server's actual `tiles[0].width` from `info.json` for tightest
    cache alignment with the server's pre-computed tiles.

  * `tile_height` — defaults to `tile_width` (square tiles).

  * `scale_factor` — integer; the tiles cover `tile_width *
    scale_factor` source pixels each, rendered at `tile_width`.
    `1` is full resolution. Higher = more pixels per tile, fewer
    tiles total. Defaults to `1`.

  * `format`, `iiif_quality` — applied to every tile URL. Default
    `:jpeg` and `:default`.

  Viewer mode (`mode={:viewer}`):

  * `width`, `height` — pixel size of the viewer container. CSS
    pixels. Defaults to `800` × `600`.

  * `viewer` — informational atom passed through as
    `data-iiif-viewer="…"` so a JS hook can dispatch on viewer
    family. Defaults to `:openseadragon`. Other common values:
    `:mirador`, `:leaflet`.

  * `fallback_size` — width passed to the static fallback `<img>`
    inside the viewer div. Shown before JS mounts. Defaults to
    `800`.

  * Any `phx-hook=…`, `id=…`, `class=…`, or other HTML attributes
    pass through to the outer `<div>` via `:rest`.

  ### Returns

  * Renders an `<img>` (static), a wrapper `<div>` containing
    a CSS grid of `<img>` tiles (tiles), or a wrapper `<div>`
    with viewer-mount data attributes plus a fallback `<img>`
    (viewer).

  """
  attr :src, :string, required: true
  attr :host, :string, default: ""
  attr :iiif_prefix, :string, default: "/iiif/3"
  attr :mode, :atom, values: [:static, :tiles, :viewer], default: :static

  # Static-mode attrs (shared with <.image>).
  attr :width, :integer, default: nil
  attr :height, :integer, default: nil
  attr :fit, :atom, default: nil
  attr :region, :any, default: nil
  attr :iiif_quality, :atom, values: [:default, :color, :gray, :bitonal, nil], default: nil
  attr :format, :atom, default: nil
  attr :iiif_format, :atom, default: :jpeg

  # Tiles-mode attrs.
  attr :source_width, :integer, default: nil
  attr :source_height, :integer, default: nil
  attr :tile_width, :integer, default: 512
  attr :tile_height, :integer, default: nil
  attr :scale_factor, :integer, default: 1

  # Viewer-mode attrs.
  attr :viewer, :atom, default: :openseadragon
  attr :fallback_size, :integer, default: 800

  attr :rest, :global,
    include: ~w(alt class id loading decoding fetchpriority phx-hook phx-update style)

  def iiif(%{mode: :static} = assigns), do: render_static(assigns)
  def iiif(%{mode: :tiles} = assigns), do: render_tiles(assigns)
  def iiif(%{mode: :viewer} = assigns), do: render_viewer(assigns)

  # ── :static ─────────────────────────────────────────────────────

  defp render_static(assigns) do
    pipeline = build_static_pipeline(assigns)

    assigns =
      assign(assigns, :__src,
        URL.iiif(pipeline,
          source_path: assigns.src,
          host: assigns.host,
          iiif_prefix: assigns.iiif_prefix,
          iiif_format: assigns.iiif_format
        )
      )

    ~H"""
    <img src={@__src} {@rest} />
    """
  end

  defp build_static_pipeline(assigns) do
    resize_fields =
      [
        width: assigns[:width],
        height: assigns[:height],
        fit: assigns[:fit]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    format_fields =
      [type: assigns[:format]]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    ops =
      []
      |> maybe_prepend_resize(resize_fields)
      |> maybe_prepend_quality(assigns[:iiif_quality])
      |> maybe_prepend_region(assigns[:region])

    output =
      case format_fields do
        [] -> nil
        fs -> struct(Ops.Format, fs)
      end

    %Pipeline{ops: ops, output: output}
  end

  defp maybe_prepend_resize(ops, []), do: ops
  defp maybe_prepend_resize(ops, fs), do: [struct(Ops.Resize, fs) | ops]

  defp maybe_prepend_quality(ops, nil), do: ops
  defp maybe_prepend_quality(ops, :default), do: ops
  defp maybe_prepend_quality(ops, :color), do: ops

  defp maybe_prepend_quality(ops, :gray) do
    [%Ops.Adjust{saturation: 0.0} | ops]
  end

  defp maybe_prepend_quality(ops, :bitonal) do
    [%Ops.Posterize{levels: 2} | ops]
  end

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

  # ── :tiles ──────────────────────────────────────────────────────
  #
  # IIIF tile URLs follow a per-region/per-size template:
  #
  #   {base}/{x},{y},{rw},{rh}/{w},{h}/0/{quality}.{format}
  #
  # where (x, y, rw, rh) is the region in source pixels,
  # (w, h) is the rendered tile size, and the rendered tile is a
  # downscaled view of the region: rw == w * scale_factor.
  #
  # The grid is built top-to-bottom, left-to-right; the last tile
  # in each row/column is clipped to whatever source pixels are
  # left, so the bottom-right tile is typically smaller than the
  # rest. The renderer doesn't pad — the grid mirrors the source
  # aspect.

  defp render_tiles(assigns) do
    if is_nil(assigns.source_width) or is_nil(assigns.source_height) do
      raise ArgumentError, """
      `<.iiif mode={:tiles}>` requires `source_width` and `source_height`
      attributes (the source image's pixel dimensions). Discover them
      from the IIIF info.json document. Got src=#{inspect(assigns.src)}.
      """
    end

    tile_height = assigns.tile_height || assigns.tile_width

    tiles =
      build_tile_grid(
        assigns.source_width,
        assigns.source_height,
        assigns.tile_width,
        tile_height,
        assigns.scale_factor
      )
      |> Enum.map(fn tile ->
        Map.put(tile, :url, build_tile_url(tile, assigns))
      end)

    rendered_w = ceil_div(assigns.source_width, assigns.scale_factor)
    rendered_h = ceil_div(assigns.source_height, assigns.scale_factor)

    cols = length(Enum.uniq_by(tiles, & &1.x))
    grid_template_columns = String.duplicate("auto ", cols) |> String.trim()

    assigns =
      assign(assigns,
        tiles: tiles,
        grid_template_columns: grid_template_columns,
        rendered_width: rendered_w,
        rendered_height: rendered_h
      )

    ~H"""
    <div
      style={"display:grid;grid-template-columns:#{@grid_template_columns};width:#{@rendered_width}px;height:#{@rendered_height}px;line-height:0;"}
      {@rest}
    >
      <img :for={tile <- @tiles} src={tile.url} width={tile.rendered_w} height={tile.rendered_h} />
    </div>
    """
  end

  # Walks the source pixel space in row-major order, emitting a
  # tile descriptor per cell. The last tile in each axis is
  # clipped to the remaining source pixels (so an N×N source with
  # tile T may produce a final partial tile of T-mod-N pixels).
  defp build_tile_grid(src_w, src_h, tile_w, tile_h, scale) do
    region_w = tile_w * scale
    region_h = tile_h * scale

    for y <- 0..(src_h - 1)//region_h,
        x <- 0..(src_w - 1)//region_w do
      remaining_w = min(region_w, src_w - x)
      remaining_h = min(region_h, src_h - y)
      rendered_w = ceil_div(remaining_w, scale)
      rendered_h = ceil_div(remaining_h, scale)

      %{
        x: x,
        y: y,
        region_w: remaining_w,
        region_h: remaining_h,
        rendered_w: rendered_w,
        rendered_h: rendered_h
      }
    end
  end

  defp build_tile_url(tile, assigns) do
    quality = iiif_quality_token(assigns.iiif_quality)
    format = iiif_format_token(assigns.format || assigns.iiif_format)
    identifier_path = "#{assigns.host}#{assigns.iiif_prefix}/#{encode_identifier(assigns.src)}"

    region = "#{tile.x},#{tile.y},#{tile.region_w},#{tile.region_h}"
    size = "#{tile.rendered_w},#{tile.rendered_h}"

    "#{identifier_path}/#{region}/#{size}/0/#{quality}.#{format}"
  end

  defp iiif_quality_token(:gray), do: "gray"
  defp iiif_quality_token(:bitonal), do: "bitonal"
  defp iiif_quality_token(:color), do: "color"
  defp iiif_quality_token(_), do: "default"

  defp iiif_format_token(:jpeg), do: "jpg"
  defp iiif_format_token(:png), do: "png"
  defp iiif_format_token(:webp), do: "webp"
  defp iiif_format_token(:gif), do: "gif"
  defp iiif_format_token(:tiff), do: "tif"
  defp iiif_format_token(:jp2), do: "jp2"
  defp iiif_format_token(_), do: "jpg"

  # Strip leading slash, percent-encode embedded slashes — same
  # rule as the URL builder.
  defp encode_identifier(path) do
    path
    |> String.trim_leading("/")
    |> URI.encode(&URI.char_unreserved?/1)
  end

  defp ceil_div(a, b), do: div(a + b - 1, b)

  # ── :viewer ─────────────────────────────────────────────────────
  #
  # Emits a sized container `<div>` carrying enough data attributes
  # for a deep-zoom JS viewer (OpenSeadragon, Mirador, Leaflet-IIIF)
  # to mount on. The static fallback `<img>` inside is what the user
  # sees before the JS runs (and what no-JS clients see permanently).
  #
  # We deliberately don't ship the JS — the user's app supplies it
  # via a Phoenix LiveView Hook or a plain mount script that listens
  # for elements matching `[data-iiif-viewer]`. The `data-iiif-info-url`
  # attribute is the only contract; viewers that speak IIIF Image API
  # 3.0 all read it the same way.

  defp render_viewer(assigns) do
    info_url =
      URL.iiif_info_url(
        source_path: assigns.src,
        host: assigns.host,
        iiif_prefix: assigns.iiif_prefix
      )

    width = assigns.width || 800
    height = assigns.height || 600
    fallback_size = assigns.fallback_size || width

    fallback_pipeline = %Pipeline{
      ops: [%Ops.Resize{width: fallback_size, upscale?: false}],
      output: nil
    }

    fallback_url =
      URL.iiif(fallback_pipeline,
        source_path: assigns.src,
        host: assigns.host,
        iiif_prefix: assigns.iiif_prefix,
        iiif_format: assigns.iiif_format
      )

    assigns =
      assign(assigns,
        __info_url: info_url,
        __fallback_url: fallback_url,
        __viewer_width: width,
        __viewer_height: height
      )

    ~H"""
    <div
      data-iiif-info-url={@__info_url}
      data-iiif-viewer={Atom.to_string(@viewer)}
      style={"width:#{@__viewer_width}px;height:#{@__viewer_height}px;"}
      {@rest}
    >
      <img src={@__fallback_url} style="width:100%;height:100%;object-fit:contain;" />
    </div>
    """
  end
end
