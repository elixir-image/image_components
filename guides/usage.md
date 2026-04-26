# User guide

A practical walkthrough for `image_components`: install, render responsive markup, pick the right layout mode, do art-direction, point at a remote CDN, and avoid the common pitfalls.

For the underlying URL grammar, see [`image_plug`](https://hex.pm/packages/image_plug). For per-module API reference, see the generated module docs.

## Contents

* [Installation](#installation)
* [`<.image>` quick start](#image-quick-start)
* [Layout modes](#layout-modes)
* [Format negotiation: `:formats`](#format-negotiation-formats)
* [Art direction: `<.picture>`](#art-direction-picture)
* [Performance: `priority`, `loading`, CLS](#performance-priority-loading-cls)
* [Cross-host CDN: `:host`](#cross-host-cdn-host)
* [Application-level defaults](#application-level-defaults)
* [Picking a CDN: `:cdn`](#picking-a-cdn-cdn)
* [Forwarding extra options: `:url_options`](#forwarding-extra-options-url_options)
* [Signed URLs](#signed-urls)
* [Configuration reference](#configuration-reference)
* [Best practices](#best-practices)
* [Caveats](#caveats)

## Installation

```elixir
def deps do
  [
    {:image_components, "~> 0.1"},
    {:phoenix_live_view, "~> 1.0"}
  ]
end
```

The image-server back-end is deployed separately. Use [`image_plug`](https://hex.pm/packages/image_plug) for an Elixir-native deployment, or point at your Cloudflare / imgix / Cloudinary / ImageKit subdomain for the corresponding hosted service. The component speaks all four URL grammars; see [Picking a CDN](#picking-a-cdn-cdn).

## `<.image>` quick start

Import the module in any LiveView, function component, or template:

```elixir
defmodule MyAppWeb.PageLive do
  use MyAppWeb, :live_view
  import Image.Component
  ...
end
```

Then in your template:

```heex
<.image
  src="/photos/sunset.jpg"
  alt="Sunset over the harbour"
  width={1600}
  height={900}
  sizes="(min-width: 1200px) 800px, (min-width: 768px) 50vw, 100vw"
  formats={[:avif, :webp]}
  priority={:lcp}
/>
```

Renders a `<picture>` with one `<source type="image/avif">` and one `<source type="image/webp">`, plus a fallback `<img>` carrying:

* a width-descriptor srcset (`/cdn-cgi/image/format=avif,width=320/photos/sunset.jpg 320w, …, width=1600 1600w`),
* the supplied `sizes`, `alt`, `width`, `height`,
* `loading="eager"` and `fetchpriority="high"` because `priority: :lcp`,
* `decoding="async"`,
* `style="max-width: 1600px; width: 100%; height: auto; aspect-ratio: 1600 / 900;"` to prevent CLS.

## Layout modes

Three modes mirror [`@unpic/core`](https://github.com/ascorbic/unpic-img/tree/main/packages/core/src):

### `:constrained` (default)

The image scales down with its container but never up beyond its intrinsic width. Width-descriptor srcset capped at the intrinsic width. The default for content images, hero images, body images.

```heex
<.image src="/photo.jpg" alt="" width={1200} height={800}
        sizes="(min-width: 768px) 50vw, 100vw" />
```

### `:fixed`

The image renders at a single intrinsic size regardless of viewport. Density-descriptor srcset (`1x`, `2x`, `3x`). Use for logos, fixed-size avatars, icons.

```heex
<.image src="/avatar.png" alt="" width={64} height={64} layout={:fixed} />
```

`:sizes` is ignored for `:fixed` (the browser only selects on DPR).

### `:full_width`

The image always fills the viewport (or its container, when CSS bounds it). Width-descriptor srcset over a wider default ladder.

```heex
<.image src="/banner.jpg" alt="" layout={:full_width} sizes="100vw" />
```

Each mode emits the appropriate inline `style` so layout space is reserved before the image loads — preventing Cumulative Layout Shift.

## Format negotiation: `:formats`

The `formats` attr renders a `<picture>` with one `<source type=...>` per format, plus the fallback `<img>`. Browsers walk the sources in order and pick the first they support. Canonical 2025 ordering: AVIF first, then WebP.

```heex
<.image src="/photo.jpg" alt="" width={1200} height={800}
        sizes="100vw" formats={[:avif, :webp]} />
```

If you don't pass `:formats`, the component renders a bare `<img>` with no `<picture>` wrapper. The fallback `<img>` always uses the source's native format unless you override via `:url_options`.

For format negotiation alone (no art direction), prefer this `formats:` approach over `<.picture>`. It's less ceremony for the same `<picture>` markup.

## Art direction: `<.picture>`

When the *crop or aspect ratio* should differ at different breakpoints, use `Image.Component.Picture.picture/1`:

```heex
<Image.Component.Picture.picture
  alt="Portrait of the founder"
  sources={[
    %{
      media: "(min-width: 1024px)",
      src: "/founder.jpg",
      url_options: [fit: :cover, gravity: :face],
      width: 1200,
      height: 800,
      sizes: "1200px",
      formats: [:avif, :webp]
    },
    %{
      media: "(min-width: 480px)",
      src: "/founder.jpg",
      url_options: [fit: :cover, gravity: :face],
      width: 800,
      height: 1000,
      sizes: "100vw",
      formats: [:avif, :webp]
    }
  ]}
  fallback={%{
    src: "/founder.jpg",
    url_options: [fit: :cover, gravity: :face],
    width: 480,
    height: 600,
    sizes: "100vw"
  }}
  priority={:lcp}
/>
```

Each `:sources` entry has its own `:media` query, intrinsic dimensions, sizes, formats, and url_options. The first source whose media query matches wins. The `:fallback` is the final `<img>` — used when no media query matches *or* when the browser doesn't support `<picture>` (very rare in 2025).

Don't reach for `<.picture>` just to do AVIF/WebP fallback. `<.image formats={[:avif, :webp]}>` does that with less ceremony. Use `<.picture>` when the crop genuinely changes across breakpoints (a vertical portrait on mobile vs a horizontal hero on desktop, with different focal points).

## Performance: `priority`, `loading`, CLS

Three patterns dominate.

### LCP / above-the-fold

```heex
<.image src="/hero.jpg" alt="" width={1600} height={900}
        sizes="100vw" priority={:lcp} formats={[:avif, :webp]} />
```

`priority: :lcp` sets `loading="eager"` and `fetchpriority="high"`. This is the modern replacement for `<link rel="preload" as="image">` for in-DOM hero images ([web.dev "Optimize LCP"](https://web.dev/articles/optimize-lcp)).

### Below-the-fold

```heex
<.image src="/gallery/12.jpg" alt="" width={400} height={300} sizes="400px" />
```

Default `loading="lazy"` lets the browser defer until the image is near the viewport. Don't apply this to the LCP image.

### CLS prevention

Always set `width` and `height`. The component emits inline `style="aspect-ratio: W / H;"` so the browser reserves the right amount of layout space before the bytes arrive. Skipping these is the single biggest cause of CLS in image-heavy pages.

`decoding="async"` is set on every image. No knob.

## Cross-host CDN: `:host`

By default, generated URLs are root-relative — they target the same host the LiveView is rendered from. Pass `:host` to point at a different deployment:

```heex
<.image src="/sunset.jpg" alt="" width={1600} height={900}
        host="img.example.com" />
```

Resolves URLs like `https://img.example.com/cdn-cgi/image/width=320/sunset.jpg`. Useful when:

* Your `image_plug` runs on a separate subdomain (`img.example.com` while your app is on `app.example.com`).
* You're targeting Cloudflare's hosted Images service directly (`imagedelivery.net/<account>/...` — though for that form you'd use the hosted-URL grammar directly).
* You're A/B-testing two image-server deployments by switching `:host`.

`:scheme` defaults to `"https"`. For local development:

```heex
<.image src="/sunset.jpg" alt="" width={1600} height={900}
        host="localhost:4001" scheme="http" />
```

Or include the scheme directly in `:host`:

```heex
<.image src="/sunset.jpg" alt="" width={1600} height={900}
        host="https://img.staging.example.com" />
```

This option mirrors [`unpic`](https://github.com/ascorbic/unpic)'s `domain` option.

## Application-level defaults

Every per-call attr (`:host`, `:scheme`, `:mount`, `:signing_keys`, `:signing_expires_at`, `:url_options`, `:cdn`) can be defaulted via `Application.get_env(:image_components, :defaults, [])`. Per-call attrs win when explicitly set; otherwise the env value is used.

The canonical use case is per-environment image-server configuration without touching every component call site:

```elixir
# config/dev.exs
config :image_components,
  defaults: [
    host: "localhost:4001",
    scheme: "http"
  ]

# config/prod.exs
config :image_components,
  defaults: [
    host: "imagedelivery.net/abc123hash",
    signing_keys: [System.fetch_env!("IMAGE_SIGNING_KEY")]
  ]
```

Then every `<.image src="..." width=... ... />` automatically points at the right backend. In dev: `http://localhost:4001/cdn-cgi/image/.../foo.jpg`. In prod: `https://imagedelivery.net/abc123hash/cdn-cgi/image/.../foo.jpg?sig=...`.

For `:url_options`, the env defaults *merge* with per-call values (per-call wins on key conflict):

```elixir
config :image_components,
  defaults: [url_options: [quality: 80, format: :auto]]
```

```heex
<%!-- emits format=auto, quality=80 --%>
<.image src="/photo.jpg" alt="" width={400} height={300} sizes="100vw" />

<%!-- emits format=auto, quality=90 — quality from per-call wins --%>
<.image src="/photo.jpg" alt="" width={400} height={300} sizes="100vw"
        url_options={[quality: 90]} />
```

## Picking a CDN: `:cdn`

The `:cdn` config selects the URL/signing adapter. Atoms map to built-in adapters; modules let you plug in custom ones.

Built-in adapters:

* `:cloudflare` (default) — `Image.Component.CDN.Cloudflare`. Path-segment grammar (`/cdn-cgi/image/<options>/<source>`). Wire-format-compatible with both [`image_plug`](https://hex.pm/packages/image_plug) configured with `Image.Plug.Provider.Cloudflare` and Cloudflare's hosted Images service.

* `:imgix` — `Image.Component.CDN.Imgix`. Query-string grammar (`/<source>?w=400&fm=webp`). Wire-format-compatible with both `image_plug` configured with `Image.Plug.Provider.Imgix` and imgix's hosted service.

* `:cloudinary` — `Image.Component.CDN.Cloudinary`. Account-prefixed path grammar (`/<account>/image/upload/<transforms>/<source>`). Wire-format-compatible with both `image_plug` configured with `Image.Plug.Provider.Cloudinary` and Cloudinary's hosted service. Requires `:account` (your Cloudinary cloud name) — pass per-call via `:url_options` or set as a default.

* `:image_kit` — `Image.Component.CDN.ImageKit`. `tr:`-prefix grammar (`/<endpoint>/tr:w-400,f-webp/<source>`). Wire-format-compatible with both `image_plug` configured with `Image.Plug.Provider.ImageKit` and ImageKit's hosted service.

```elixir
# Configure Cloudflare (this is also the default if :cdn is omitted).
config :image_components,
  defaults: [cdn: :cloudflare]

# Or imgix:
config :image_components,
  defaults: [
    cdn: :imgix,
    host: "example.imgix.net"
  ]

# Or Cloudinary:
config :image_components,
  defaults: [
    cdn: :cloudinary,
    host: "res.cloudinary.com",
    url_options: [account: "your_cloud_name"]
  ]

# Or ImageKit:
config :image_components,
  defaults: [
    cdn: :image_kit,
    host: "ik.imagekit.io",
    url_options: [endpoint: "your_imagekit_id"]
  ]
```

Per-call override:

```heex
<.image cdn={:cloudflare} ... />
<.image cdn={:imgix} ... />
<.image cdn={:cloudinary} ... />
<.image cdn={:image_kit} ... />
<.image cdn={MyApp.MyCustomCDN} ... />
<.image cdn={{MyApp.MyCustomCDN, [some_opt: true]}} ... />
```

The same canonical option keys (`:width`, `:height`, `:fit`, `:gravity`, `:format`, `:quality`, `:blur`, `:sharpen`, `:brightness`, `:contrast`, `:saturation`, `:background`) work across every adapter. Each adapter translates them to the wire vocabulary its back-end speaks: `width=`/`fit=cover` for Cloudflare, `w=`/`fit=crop` for imgix, `w_`/`c_fill` for Cloudinary, `w-`/`c-extract` for ImageKit. Migrating between back-ends is a one-line `:cdn` change — no template edits.

### Worked example: pointing the same markup at imgix

```elixir
# config/prod.exs
config :image_components,
  defaults: [
    cdn: :imgix,
    host: "example.imgix.net",
    signing_keys: [System.fetch_env!("IMGIX_SIGNING_KEY")]
  ]
```

```heex
<.image
  src="/photos/sunset.jpg"
  alt="Sunset"
  width={1200}
  height={800}
  sizes="100vw"
  formats={[:avif, :webp]}
  url_options={[fit: :cover, quality: 80]}
/>
```

Renders srcset entries like `https://example.imgix.net/photos/sunset.jpg?fit=crop&fm=avif&q=80&s=<hex>&w=320` — the same markup that emits `/cdn-cgi/image/...` URLs under the `:cloudflare` adapter.

### Adding a custom adapter

Implement `Image.Component.CDN` (`build_url/2` + `sign_url/3`). See the [`Image.Component.CDN.Cloudflare`](https://hexdocs.pm/image_components/Image.Component.CDN.Cloudflare.html), [`Image.Component.CDN.Imgix`](https://hexdocs.pm/image_components/Image.Component.CDN.Imgix.html), [`Image.Component.CDN.Cloudinary`](https://hexdocs.pm/image_components/Image.Component.CDN.Cloudinary.html), and [`Image.Component.CDN.ImageKit`](https://hexdocs.pm/image_components/Image.Component.CDN.ImageKit.html) sources for one-screen reference implementations.

## Forwarding extra options: `:url_options`

Every URL option that isn't a top-level component attr can be passed via `:url_options`. The component embeds them in every URL it generates (alongside the per-srcset-entry `width=`).

```heex
<.image src="/photo.jpg" alt="" width={1200} height={800} sizes="100vw"
        url_options={[fit: :cover, quality: 80, gravity: :face, blur: 5]} />
```

The keys are canonical (`:fit`, `:quality`, `:gravity`, `:blur`, etc.) — the configured `:cdn` adapter translates them to the wire vocabulary the back-end speaks. Under `:cloudflare` you get `fit=cover,quality=80,gravity=face,blur=5`; under `:imgix` you get `blur=500&fit=crop&q=80`.

The encoder filters values it doesn't recognise (e.g. `quality: 999` is silently dropped because the encoder only emits integers in `1..100`). This means the component cannot produce a URL the back-end will reject for those keys — by design.

## Signed URLs

When your `image_plug` deployment is configured with `:signing`, every request must carry a valid `?sig=<hex>` parameter. Pass `:signing_keys` to the component and it signs every URL it emits:

```heex
<.image
  src="/photos/sunset.jpg"
  alt=""
  width={1200}
  height={800}
  sizes="100vw"
  signing_keys={[Application.fetch_env!(:my_app, :image_signing_key)]}
/>
```

Both ends of the wire share the format (HMAC over the path-and-query, hex- or base64url-encoded). The selected `:cdn` adapter chooses the algorithm, parameter name, and canonical-string rule:

* `:cloudflare` appends `?sig=<hex>` (HMAC-SHA256). Uses the secret only as the HMAC key.

* `:imgix` appends `?s=<hex>` (HMAC-SHA256). Prepends the secret to the payload (matching imgix's wire format).

* `:cloudinary` inserts an in-path segment `s--<sig>--` (SHA-256 over `<transforms>/<source><api-secret>`, truncated to 32 url-safe-base64 characters).

* `:image_kit` appends `?ik-s=<hex>` (HMAC-SHA1). Uses the secret as the HMAC key.

If the back-end's `:signing.keys` includes the same key, every URL the component generates verifies — regardless of which adapter you've chosen.

### Expiry

Pass a `DateTime` or unix-seconds value via `:signing_expires_at`:

```heex
<.image
  src="/photos/sunset.jpg"
  alt=""
  width={1200}
  height={800}
  sizes="100vw"
  signing_keys={["secret"]}
  signing_expires_at={DateTime.utc_now() |> DateTime.add(3600, :second)}
/>
```

Use sparingly. Per-request expiry breaks CDN caching (each render produces a new URL with a new `?exp` and a new signature, so the cache key changes). Better practice: set a long expiry on a stable key, rotate the key occasionally.

### Key rotation from the client side

When the back-end rotates keys, update `:signing_keys` in the component to the new (first) key. Cached responses signed with the old key keep working until they're evicted from the CDN.

### Caveats

* `:signing_keys` must be a non-empty list. The first key is used for signing; the rest don't matter on the client side (they're only relevant to the back-end's verifier).

* A signed URL is bound to its path. If you change `:url_options` between the original sign-time and a re-render, the new URL gets a new signature — old caches return 304 against new requests and the bytes match (because the underlying transform is identical).

* `:signing_keys` interacts with `:host`: the component signs only the path portion (no origin), matching how `Image.Plug` verifies. You can change `:host` between sign-time and the request without invalidating the signature.

## Configuration reference

`Image.Component.image/1` attrs:

| Attr | Default | Meaning |
| --- | --- | --- |
| `:src` | required | Source path or absolute URL. |
| `:alt` | required | Alt text. Pass `""` for purely decorative images. |
| `:sizes` | `"100vw"` (width layouts) / `nil` (fixed) | The `sizes` attribute. Compute from CSS rendered widths per breakpoint. |
| `:width` | nil | Intrinsic display width in CSS pixels. Required for `:fixed` and `:constrained`. |
| `:height` | nil | Intrinsic display height. Strongly recommended for CLS prevention. |
| `:layout` | `:constrained` | `:fixed` \| `:constrained` \| `:full_width`. |
| `:widths` | layout default | Override the layout's width ladder. |
| `:max_width` | nil | Cap the width ladder. |
| `:formats` | `[]` | Format atoms for `<picture>` `<source type=...>` entries. Empty = bare `<img>`. |
| `:loading` | `:lazy` | `:lazy` \| `:eager` \| `:auto`. |
| `:priority` | `:normal` | `:lcp` promotes to `loading="eager" fetchpriority="high"`. |
| `:host` | nil | Origin to prefix all URLs with. |
| `:scheme` | `"https"` | Scheme when `:host` is bare. |
| `:mount` | `""` | Path prefix the receiving image plug is mounted under. |
| `:url_options` | `[]` | Extra canonical URL options (e.g. `[fit: :cover, quality: 80]`) applied to every URL. The configured `:cdn` adapter translates to the back-end's wire vocabulary. |
| `:signing_keys` | nil | Non-empty list of HMAC secrets. When set, every URL is signed via `Image.Component.Signing.sign/3`. |
| `:signing_expires_at` | nil | `DateTime` or unix-seconds. Adds an expiry parameter to every URL (`?exp=<unix>` for Cloudflare, `?expires=<unix>` for imgix); back-end rejects after this time. |
| `:cdn` | `:cloudflare` | CDN adapter selection. Atom shorthand, module name, or `{module, opts}` tuple. See `Image.Component.CDN`. |

Every per-call attr can be defaulted via `Application.get_env(:image_components, :defaults, [])`. Per-call wins when explicitly set.

`Image.Component.Picture.picture/1` attrs share the performance + cross-host + adapter attrs (`priority`, `loading`, `host`, `scheme`, `mount`, `cdn`) plus `:sources` (list of source maps) and `:fallback` (single fallback map). Each source/fallback map accepts the per-image attrs above (including `:url_options`, `:formats`, `:signing_keys`, `:signing_expires_at`).

## Best practices

### Pick the right layout

* `:constrained` for content images (the default and right answer most of the time).
* `:fixed` for logos, fixed-size avatars, and icons. Avoids the `Vary: Accept` cache fragmentation that DPR-descriptor srcsets cause.
* `:full_width` only for true edge-to-edge banners.

### Write `sizes` correctly

`sizes` describes the rendered CSS width per breakpoint, not the viewport. Common mistakes:

* Using `100vw` for an image inside a constrained container — over-fetches.
* Using a fixed CSS value when the image is fluid — under-fetches on retina.
* Forgetting horizontal padding/gutters — the image's actual width is less than the column.

Compute from your CSS, not from your gut. If you have a 1200px max-width container with 50vw image at desktop and full-width at mobile:

```
sizes="(min-width: 1200px) 600px, (min-width: 768px) 50vw, 100vw"
```

### LCP image attributes

Set `priority: :lcp` on the largest above-the-fold image. Combined with `loading="eager"` (auto) and `fetchpriority="high"` (auto), this is the Google-recommended pattern for hero images.

### `formats` for content, native for chrome

Content images: `formats: [:avif, :webp]` for AVIF/WebP fallback to JPEG.

UI chrome (logos, buttons, icons): use SVG where possible, or a single PNG/WebP — no `formats` list. The byte savings are tiny relative to the markup overhead.

### CLS hygiene

Always set `width` and `height`. If you don't know the intrinsic size, fetch it once and cache. The CLS penalty for forgetting is real and the fix is mechanical.

### Cache friendliness

`Image.Component.URL.build/2` sorts options alphabetically before joining. Two callers passing the same options in different order produce identical URLs (and identical ETags from `image_plug`). You don't need to do anything to benefit; just know that re-ordering options is a no-op for caches.

## Caveats

### Phoenix.Component dependency

`image_components` declares `phoenix_live_view` as a hard dep. If you're using vanilla Plug without Phoenix, the URL/Srcset modules (`Image.Component.URL`, `Image.Component.Srcset`) are still useful — they're conn-agnostic — but the `<.image>` and `<.picture>` components require `Phoenix.Component`.

### Encoder validation gaps

The URL builder is permissive about value types (e.g. `quality: 999` doesn't raise; it silently drops the option). This is by design — the component is upstream of the back-end's validation. If you need strict validation, validate before passing to `:url_options`.

### Density srcsets and `format=auto`

For `:fixed` layouts the srcset uses density descriptors (`1x`, `2x`, `3x`). Density descriptors don't trigger format negotiation per `Vary: Accept` the way width descriptors do. If you want format negotiation on a fixed-size image, use `:constrained` with a single width entry instead.

### `<picture>` in print

`<picture>` markup degrades cleanly in print (the `<img>` always renders) but the format selection happens at media-query evaluation time. If you care about print accuracy, audit your `:formats` list and consider serving JPEG only for print-targeted CSS.

## Where to go next

* The `Image.Component` moduledoc — full attrs reference.
* The `Image.Component.Picture` moduledoc — art-direction `<picture>`.
* The `Image.Component.CDN` moduledoc — adapter behaviour and seam for adding new CDNs.
* [`image_plug` user guide](https://hexdocs.pm/image_plug/usage.html) — the back-end this component talks to.
* [`image_plug` Cloudflare conformance guide](https://hexdocs.pm/image_plug/cloudflare_conformance.html).
* [`image_plug` imgix conformance guide](https://hexdocs.pm/image_plug/imgix_conformance.html).
* [`image_plug` Cloudinary conformance guide](https://hexdocs.pm/image_plug/cloudinary_conformance.html).
* [`image_plug` ImageKit conformance guide](https://hexdocs.pm/image_plug/image_kit_conformance.html).

