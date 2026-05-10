# IIIF Image API 3.0

`Image.Components` ships a fifth provider — `:iiif` — that emits URLs in the [IIIF Image API 3.0](https://iiif.io/api/image/3.0/) URL grammar. IIIF is different from the four CDN providers: it's an open standard published by the [IIIF Consortium](https://iiif.io), not a single vendor's URL syntax, and dozens of cultural-heritage institutions and image servers (Cantaloupe, IIPImage, Loris, Hyrax, Goobi viewer, Universal Viewer's backends) implement it. Use `:iiif` when your image source is a IIIF-compliant server — Wellcome Collection, Library of Congress, Yale's IIIF deployments, Bodleian, an institutional Cantaloupe instance, or your own [`image_plug`](https://hex.pm/packages/image_plug) IIIF mount (the symmetric server-side parser, see "Use against a self-hosted `image_plug` IIIF mount" below).

## URL shape

```
{host}{prefix}/{identifier}/{region}/{size}/{rotation}/{quality}.{format}
```

The five positional segments after the identifier are always present — IIIF servers reject URLs missing any segment.

## Quick start

```heex
<.image
  src="/V0007727.jpg"
  provider={:iiif}
  host="https://iiif.wellcomecollection.org"
  iiif_prefix="/image"
  width={400}
/>
```

Renders to:

```html
<img src="https://iiif.wellcomecollection.org/image/V0007727.jpg/full/^400,/0/default.jpg" />
```

The `iiif_prefix` here is `"/image"` because Wellcome's server publishes under that prefix; for a vanilla Image API 3.0 server the prefix is typically `"/iiif/3"` (the default).

## What maps and what doesn't

| Component attribute | IIIF segment | Notes |
| --- | --- | --- |
| `src=`              | `{identifier}` | Leading `/` stripped; embedded `/` percent-encoded as `%2F` |
| `width`, `height`, `fit`, `dpr` | `{size}` | `fit: :contain` → `!w,h`; `fit: :squeeze` → `w,h` (distort); width-only → `w,`; height-only → `,h`; `Resize.upscale?` toggles the `^` prefix |
| `region={...}`      | `{region}` | `:full`, `{:pixels, x, y, w, h}`, or `{:percent, x, y, w, h}` |
| `Rotate{angle: …}`  | `{rotation}` | Any 0..360 (3.0 allows arbitrary angles) |
| `iiif_quality=`     | `{quality}` | `:default`, `:color`, `:gray`, `:bitonal` |
| `format`            | `{format}` | `:jpeg`→`jpg`, `:webp`, `:png`, `:gif`, `:tiff`→`tif`, `:jp2`, `:pdf`. `:auto` falls back to `iiif_format=` (default `:jpeg`) |

Concepts that have no IIIF equivalent and are silently dropped:

* **Effects** — `blur`, `sharpen`, `vignette`, `tint`. IIIF's spec deliberately scopes to geometric transforms and a small fixed quality vocabulary. Effects are out of scope.
* **`fit: :cover`** — IIIF cannot express "scale-to-fill plus centred crop" in one URL. Use `:contain` or `:squeeze`, or supply an explicit `region={...}` for the sub-rectangle you want.
* **`Adjust` (non-grayscale)** — brightness/contrast/saturation/gamma have no IIIF parameter. Only `Adjust{saturation: 0.0}` round-trips, via the `gray` quality token.
* **`face_zoom`, `gravity`** — IIIF has no face-aware crop concept.

A pipeline that uses any of the dropped ops still produces a valid IIIF URL — the dropped ops just don't appear in it. If your app needs effects, render against a CDN provider; if your app needs IIIF compatibility, scope the IR to what IIIF can carry.

## Region

`region=` is the IIIF-specific attribute that no other provider in this library carries. Three shapes:

```heex
<%!-- The whole image (the default; same as omitting region=) --%>
<.image src="/cat.jpg" provider={:iiif} region={:full} />

<%!-- Pixel rectangle: x, y, width, height --%>
<.image src="/cat.jpg" provider={:iiif} region={{:pixels, 100, 50, 400, 300}} />

<%!-- Percentage rectangle (0..100 each) --%>
<.image src="/cat.jpg" provider={:iiif} region={{:percent, 25.0, 25.0, 50.0, 50.0}} />
```

The pixel form maps to IIIF `x,y,w,h`; the percent form to `pct:x,y,w,h`; `:full` (or omitted) to `full`. The IR carries the rectangle as `Image.Plug.Pipeline.Ops.Crop`, which `image_plug`'s interpreter applies before the resize step (matching the IIIF spec's `region → size` order).

The IIIF spec also defines a `square` region that crops the largest centered square. The library doesn't currently project to `square` — use `{:percent, …}` with explicit dimensions if you need a centered square.

## Quality

IIIF has four named quality values: `default`, `color`, `gray`, `bitonal`. Most servers treat `default` and `color` identically; `gray` is luminance-only; `bitonal` is one-bit-per-pixel black-and-white.

```heex
<.image src="/cat.jpg" provider={:iiif} iiif_quality={:gray} />
<.image src="/cat.jpg" provider={:iiif} iiif_quality={:bitonal} />
```

Behind the scenes:

* `iiif_quality={:gray}` injects an `Ops.Adjust{saturation: 0.0}` op into the pipeline.
* `iiif_quality={:bitonal}` injects an `Ops.Posterize{levels: 2}` op.

Both are detected by the projector when emitting the URL's quality segment. The same trick lets you achieve the same IIIF URL output by setting saturation or posterize directly on the IR — useful when your code already builds pipelines for one of the CDN providers and you want to render the same data via IIIF.

Don't confuse `iiif_quality=` (the IIIF quality token) with `quality=` (the integer `1..100` compression quality used by every other provider). They are unrelated; IIIF servers don't accept a numeric quality.

## Rotation

IIIF Image API 3.0 accepts any rotation angle 0..360. We project `Ops.Rotate.angle` directly:

```heex
<.image src="/cat.jpg" provider={:iiif} width={400} />
<%!-- /iiif/3/cat.jpg/full/^400,/0/default.jpg --%>

<.image src="/cat.jpg" provider={:iiif} width={400} {%{rotate: 45}} />
<%!-- /iiif/3/cat.jpg/full/^400,/45/default.jpg (with Rotate{angle: 45} in the IR) --%>
```

IIIF servers process operations in spec-prescribed order: `region` → `size` → `rotation` → `quality` → `format`. So a width-then-rotate will resize first, then rotate the resized image. A 4:3 source resized to width=400 becomes 400×300, then a 90° rotation makes it 300×400. Plan dimensions accordingly.

The IIIF spec also defines `!N` (mirror-then-rotate). The library doesn't yet project a mirror op into the rotation prefix — if you need mirroring, drop down to the URL builder and emit it manually.

## Server prefixes

`iiif_prefix=` is the segment between `host=` and the identifier. It varies by deployment:

| Server | Typical prefix |
| --- | --- |
| Cantaloupe (default config), Loris, IIPImage | `/iiif/3` |
| Wellcome Collection | `/image` |
| Library of Congress IIIF | `/image-services/iiif` |
| Custom (anything goes) | whatever the operator chose |

Always check the server's `info.json` document — its `id` field reveals the prefix the server uses.

## Pre-computing pipelines

As with the CDN providers, you can call the URL builder directly when you don't need to render HTML:

```elixir
alias Image.Components.URL
alias Image.Plug.Pipeline
alias Image.Plug.Pipeline.Ops

pipeline = %Pipeline{
  ops: [
    %Ops.Resize{width: 400, upscale?: false},
    %Ops.Rotate{angle: 90}
  ],
  output: %Ops.Format{type: :jpeg, quality: 80}
}

URL.iiif(pipeline,
  source_path: "/V0007727.jpg",
  host: "https://iiif.wellcomecollection.org",
  iiif_prefix: "/image"
)
# => "https://iiif.wellcomecollection.org/image/V0007727.jpg/full/400,/90/default.jpg"
```

`URL.iiif/2`'s docstring lists the full options surface; the same builder powers `<.image>` and `<.picture>` internally.

## Conformance level

The library targets [IIIF Image API 3.0 Compliance Level 2](https://iiif.io/api/image/3.0/compliance/), which is the level most production servers implement. URL forms outside Level 2 — IIIF authentication URLs, the `info.json` discovery document, the `services` extension — are out of scope on the **client** side. The companion `image_plug` provider is a **server**-side IIIF implementation; it ships a Level 2 parser plus an `info.json` endpoint.

The conformance gaps documented above (no `:cover` fit, effects dropped, no per-channel adjust) are deliberate semantic limits of IIIF as a standard, not omissions in this library.

## Use against a self-hosted `image_plug` IIIF mount

`image_plug` ships an `Image.Plug.Provider.IIIF` parser — the symmetric inverse of the URL builder here. Mount it in your Phoenix app to serve your own IIIF endpoint:

```elixir
forward "/iiif/3", Image.Plug,
  provider: {Image.Plug.Provider.IIIF, []},
  source_resolver: {Image.Plug.SourceResolver.File, root: "/var/lib/iiif"}
```

…and `<.image provider={:iiif} host="">` resolves through your in-process server using the same URL grammar real IIIF servers use. The mount also serves `info.json` discovery documents at `/iiif/3/<identifier>/info.json` automatically. See [`image_plug`'s IIIF conformance guide](https://hexdocs.pm/image_plug/iiif_conformance.html) for the per-segment compliance matrix and the deployment recipe.

## The IIIF-specific component: `<.iiif>`

`<.image provider={:iiif}>` covers the static-thumbnail case. `Image.Components.IIIF.iiif/1` is a dedicated IIIF component that adds two IIIF fundamentals nothing else exposes: tiled rendering and deep-zoom viewer mounting.

```elixir
import Image.Components.IIIF
```

It has three modes selected by the `mode=` attribute.

### `mode={:static}` — the default

Equivalent to `<.image provider={:iiif} src="…">`. Lives here for symmetry; if all you need is a thumbnail, the cross-provider `<.image>` is the simpler call.

```heex
<.iiif src="/cat.jpg" host="https://iiif.example.org" width={400} />
```

### `mode={:tiles}` — static tile grid

Computes the IIIF tile URLs that cover the source image at a chosen scale factor and emits a CSS-grid container of `<img>` elements. No JavaScript. Useful for high-resolution static layouts (atlases, scanned manuscripts, posters) where each tile is just one more cacheable HTTP request.

```heex
<.iiif
  src="/atlas.jpg"
  host="https://iiif.example.org"
  mode={:tiles}
  source_width={4096}
  source_height={4096}
  tile_width={512}
  scale_factor={2}
/>
```

Renders a 4×4 grid (16 tiles) where each tile covers `512 * 2 = 1024` source pixels rendered at 512 — i.e. a 2048×2048 zoomed-out view of the 4096×4096 original. Each `<img>` is a separate HTTP request to a URL like `…/0,0,1024,1024/512,512/0/default.jpg`, so the browser can parallelise the fetches and the CDN can cache each tile independently.

The component does not auto-discover the source dimensions — you supply them as `source_width=` and `source_height=`. Use `Image.Components.URL.iiif_info_url/1` to build the `info.json` URL, fetch it (e.g. in `mount/3`), and pass the resulting `width` / `height` values down. The discovery step is deliberately out of scope for the component to keep it pure render-time logic.

The bottom and right edges of the grid clip to the remaining source pixels — a 1500×1024 source with `tile_width={512}` produces a 3×2 grid where the rightmost column's `<img>` tiles are 476px wide instead of 512.

### `mode={:viewer}` — deep-zoom viewer mount

For real interactive deep-zoom (pan, pinch-zoom, full-resolution streaming) you need a JavaScript viewer — [OpenSeadragon](https://openseadragon.github.io), [Mirador](https://projectmirador.org), or [Leaflet-IIIF](https://github.com/mejackreed/Leaflet-IIIF) are the canonical choices. This mode emits the markup those viewers consume.

```heex
<.iiif
  src="/portrait.jpg"
  host="https://iiif.example.org"
  mode={:viewer}
  width={1200}
  height={900}
  viewer={:openseadragon}
  id="viewer-portrait"
  phx-hook="OpenSeadragon"
/>
```

Renders:

```html
<div
  data-iiif-info-url="https://iiif.example.org/iiif/3/portrait.jpg/info.json"
  data-iiif-viewer="openseadragon"
  style="width:1200px;height:900px;"
  id="viewer-portrait"
  phx-hook="OpenSeadragon"
>
  <img src="https://iiif.example.org/iiif/3/portrait.jpg/full/800,/0/default.jpg"
       style="width:100%;height:100%;object-fit:contain;" />
</div>
```

The fallback `<img>` is what the user sees while the JS loads (or permanently if JS is off / fails). The JS hook reads `data-iiif-info-url`, fetches `info.json`, and replaces the `<img>` with a tile-rendering canvas.

A minimal `OpenSeadragon` LiveView hook on the JS side:

```javascript
const Hooks = {
  OpenSeadragon: {
    mounted() {
      const tileSources = this.el.dataset.iiifInfoUrl
      this.viewer = OpenSeadragon({ element: this.el, tileSources, prefixUrl: "/openseadragon/" })
    },
    destroyed() { this.viewer && this.viewer.destroy() }
  }
}
```

The component does not bundle the viewer JS — that's your application's choice. Each viewer has its own license, footprint, and API; baking one in would force a decision that doesn't apply to every consumer.

## info.json discovery

Use `Image.Components.URL.iiif_info_url/1` when you need the URL of the `info.json` document — e.g. for a `<link rel="alternate">` in your page head, for a JS viewer config, or for fetching the document server-side to discover source dimensions:

```elixir
alias Image.Components.URL

URL.iiif_info_url(source_path: "/cat.jpg", host: "https://iiif.example.org")
# => "https://iiif.example.org/iiif/3/cat.jpg/info.json"
```

Same identifier-encoding rules as the regular IIIF builder: leading `/` stripped, embedded `/` percent-encoded.

## Related

* `Image.Components.URL.iiif/2` — the URL builder.
* `Image.Components.URL.iiif_info_url/1` — info.json URL builder.
* `Image.Components.IIIF.iiif/1` — the dedicated component (`:static` / `:tiles` / `:viewer`).
* [IIIF Image API 3.0 specification](https://iiif.io/api/image/3.0/) — the source of truth.
* [IIIF Cookbook](https://iiif.io/api/cookbook/) — recipes and reference URLs.
* [`environments.md`](environments.md) — how to wire `host=` and `iiif_prefix=` per environment via `Application` config.
