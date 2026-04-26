# Image.Component

Phoenix LiveView responsive-image component. Builds best-practice `<img srcset sizes>` and `<picture>` markup against any image-CDN that speaks the [Cloudflare Images URL grammar](https://developers.cloudflare.com/images/transform-images/transform-via-url/) — including [`image_plug`](https://hex.pm/packages/image_plug), Cloudflare itself, and custom Workers deployments.

## Why

Two Phoenix-LiveView idioms collide here:

* The HTML side: 2025-era responsive-image markup is non-trivial. `srcset` flavours, `sizes` attribute, `<picture type>` for AVIF/WebP/JPEG fallback, `<picture media>` for art direction, `loading`/`fetchpriority`/`decoding` for LCP and CLS. Easy to get wrong; tedious to write inline every time.

* The CDN side: every CDN has its own URL grammar for "give me this image at width N in format X". Coupling the responsive markup to a specific CDN's URL builder ties your application to that vendor.

This component decouples the two. You name the source (a path or absolute URL), the layout mode, and the desired formats. The component computes the right `srcset` / `sizes` / `<picture>` / performance attributes, building the URLs against the Cloudflare grammar your CDN already speaks.

The Cloudflare URL grammar was chosen because it's the same grammar [`unpic`](https://github.com/ascorbic/unpic) (the dominant JS responsive-image library at 131k weekly npm downloads) targets, so the algorithm is well-trodden and the URLs your component generates work against multiple back-ends.

## Installation

```elixir
def deps do
  [
    {:image_components, "~> 0.1"},
    {:phoenix_live_view, "~> 1.0"}
  ]
end
```

The image-server back-end is deployed separately. Use [`image_plug`](https://hex.pm/packages/image_plug) for an Elixir-native deployment, point at your Cloudflare zone for Cloudflare's hosted service, or any other back-end that speaks the same URL grammar.

## Quick start — `<.image>`

```heex
<.image
  src="/photos/sunset.jpg"
  alt="Sunset over the harbour"
  sizes="(min-width: 1200px) 800px, (min-width: 768px) 50vw, 100vw"
  width={1600}
  height={900}
  layout={:constrained}
  formats={[:avif, :webp]}
  priority={:lcp}
/>
```

Renders a `<picture>` with one `<source type="image/avif">` and one `<source type="image/webp">`, plus a fallback `<img>` carrying:

* a width-descriptor srcset (`/cdn-cgi/image/width=320/photos/sunset.jpg 320w, ..., width=1600 1600w`),
* the supplied `sizes`, `alt`, `width`, `height`,
* `loading="eager"` and `fetchpriority="high"` because `priority: :lcp`,
* `decoding="async"`,
* `style="max-width: 1600px; width: 100%; height: auto; aspect-ratio: 1600 / 900;"` to prevent CLS.

## Layout modes

Mirrors [`@unpic/core`](https://github.com/ascorbic/unpic-img/tree/main/packages/core/src):

* **`:constrained`** (default) — image scales down with its container but never up beyond its intrinsic width. Width-descriptor srcset capped at `width`. The default for content images.

* **`:fixed`** — image renders at a single intrinsic size regardless of viewport. Density-descriptor srcset (`1x`, `2x`, `3x`). Use for logos, fixed-size avatars, icons.

* **`:full_width`** — image always fills the viewport. Width-descriptor srcset over a wider default ladder.

Each mode emits the appropriate inline `style` to reserve layout space and prevent CLS.

## Art-direction `<.picture>`

Use `Image.Component.Picture.picture/1` when the *crop or aspect ratio* should differ at different breakpoints (true art direction), not just the resolution. Each `:sources` entry has its own `:media` query, intrinsic dimensions, and URL options:

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

For format-fallback alone (no art direction), prefer `<.image formats={[:avif, :webp]}>` — it emits the same shape with less ceremony.

## Cross-host CDN

By default, generated URLs are root-relative — they target the same host the LiveView is rendered from. To point at a different host (e.g. an `image_plug` on a separate subdomain or your Cloudflare zone), pass `:host`:

```heex
<.image src="/sunset.jpg" alt="" width={1600} height={900}
        host="img.example.com" />
```

`scheme:` defaults to `"https"`; pass `scheme: "http"` for development or include the scheme in `host` directly (`host: "https://img.example.com"`).

This mirrors `unpic`'s `domain` option.

## Configuration reference

`Image.Component.image/1` attrs:

| Attr | Default | Meaning |
| --- | --- | --- |
| `:src` | required | Source path or absolute URL. |
| `:alt` | required | Alt text. Pass `""` for purely decorative images. |
| `:sizes` | `"100vw"` (width layouts) / `nil` (fixed) | The `sizes` attribute. |
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
| `:mount` | `""` | Path prefix the image-plug is mounted under. |
| `:url_options` | `[]` | Extra Cloudflare options applied to every URL. |

## License

Apache-2.0.
