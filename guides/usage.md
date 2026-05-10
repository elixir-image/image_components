# Usage

A practical walk-through of `<.image>` and `<.picture>` and the four URL builders that back them. For an overview of what the library does and the per-CDN feature gap table, see the [README](../README.md).

## The two components

`Image.Components` exposes two function components designed to be `import`ed at the top of any LiveView or HEEx-using module:

```elixir
defmodule MyAppWeb.GalleryLive do
  use MyAppWeb, :live_view
  import Image.Components

  def render(assigns) do
    ~H"""
    <.image src="/uploads/cat.jpg" provider={:cloudflare} width={600} fit={:cover} />

    <.picture
      src="/uploads/cat.jpg"
      provider={:cloudflare}
      formats={[:avif, :webp]}
      width={1200}
    />
    """
  end
end
```

`<.image>` renders a single `<img>`; `<.picture>` renders a `<picture>` with one `<source srcset>` per format in `:formats` (default `[:avif, :webp]`) plus a fallback `<img>`. There is no JavaScript, no LiveView-specific behaviour, and no runtime overhead beyond URL string construction — both compile to plain HTML.

## How a request flows

```
                       ┌─────────────────────────────┐
  HEEx attribute set ─►│ Image.Components.image/1    │
                       │   build_pipeline/1          │
                       │   Image.Components.URL.…/2  │
                       └──────────────┬──────────────┘
                                      │  src="/img/cdn-cgi/image/…/cat.jpg"
                                      ▼
                       ┌─────────────────────────────┐
                       │ Browser fetches the URL     │
                       └──────────────┬──────────────┘
                                      ▼
                       ┌─────────────────────────────┐
                       │ image_plug forward route    │
                       │   Provider parser           │
                       │   → same Pipeline IR        │
                       │   Interpreter               │
                       │   → libvips transforms      │
                       └──────────────┬──────────────┘
                                      ▼
                            transformed bytes back
```

The IR is the contract — the four URL builders project it to URLs; the four `image_plug` providers parse those URLs back to it; the interpreter executes it against `Vix.Vips.Image`. A round-trip from attribute set to served bytes is just two ends of the same struct.

## Choosing a provider

`provider` is required and accepts one of `:cloudflare`, `:cloudinary`, `:imgix`, `:imagekit`. The four URL grammars are very different, but `Image.Components` papers over those differences: the same component call works against any of them.

```heex
<.image src="/cat.jpg" provider={:cloudflare} width={600} fit={:cover} />
<.image src="/cat.jpg" provider={:cloudinary} width={600} fit={:cover} />
<.image src="/cat.jpg" provider={:imgix}      width={600} fit={:cover} />
<.image src="/cat.jpg" provider={:imagekit}   width={600} fit={:cover} />
```

The four `src=` URLs that result are different — but each one, served by a correctly mounted `image_plug` provider, produces the same transformed image.

## Hosts and mounts

`host=` is prepended verbatim. Use it to point at a real CDN edge, or to scope under a path on your own domain:

```heex
<%!-- Self-hosted via image_plug, mounted at /img on this app --%>
<.image src="/cat.jpg" provider={:cloudflare} host="/img" />

<%!-- Real Cloudflare Images (or Cloudflare Workers) --%>
<.image src="/cat.jpg" provider={:cloudflare} host="https://images.example.com" />

<%!-- imgix source --%>
<.image src="/cat.jpg" provider={:imgix} host="https://my-source.imgix.net" />
```

The Cloudflare URL projector adds `/cdn-cgi/image/…` after the host. The Cloudinary projector adds `/<account>/image/upload/…`. Read the per-provider grammar in the README's feature gap table for details.

## Picking a face-aware crop

Use `gravity={:face}` together with `face_zoom`. `face_zoom` defaults to `0.0` which is a loose crop with full padding — usually visually indistinguishable from a centred crop. Set it to a non-zero value (Cloudflare's documented default is `0.6`) to actually see the face-aware behaviour.

```heex
<.image
  src="/portrait.jpg"
  provider={:cloudflare}
  width={300}
  height={300}
  fit={:cover}
  gravity={:face}
  face_zoom={0.6}
/>
```

Behind the scenes, `image_plug`'s `Image.Plug.FaceAware.face_crop/2` invokes `Image.FaceDetection.crop_largest/2` from `image_vision`. If `image_vision` is not in the consumer's deps, the request still succeeds — it falls through to the libvips attention-saliency crop. See [`image_plug`'s face-aware guide](https://hexdocs.pm/image_plug/face_aware.html) for the full story.

`face_zoom` projects to:

* Cloudflare: `face-zoom=<float>`
* Cloudinary: `z_<float>`
* ImageKit: `z-<float>`
* imgix: silently dropped (no equivalent in imgix's URL grammar)

## Adjust effects: per-CDN encoding

`brightness`, `contrast`, `saturation`, `gamma` are all multipliers where `1.0` means "no change", but the four CDNs encode them very differently:

```heex
<%!-- Same intent, four different on-wire URLs --%>
<.image src="/cat.jpg" provider={:cloudflare} contrast={1.4} />
<%!-- → /cdn-cgi/image/contrast=1.4/cat.jpg                      (raw multiplier) --%>

<.image src="/cat.jpg" provider={:cloudinary} contrast={1.4} />
<%!-- → /demo/image/upload/e_contrast:40/cat.jpg                 (centred percentage) --%>

<.image src="/cat.jpg" provider={:imgix} contrast={1.4} />
<%!-- → /cat.jpg?con=40                                          (centred percentage) --%>

<.image src="/cat.jpg" provider={:imagekit} contrast={1.4} />
<%!-- → /demo/cat.jpg                                            (silently dropped) --%>
```

ImageKit's URL grammar has no parameterised contrast — only an unparameterised `e-contrast` toggle. `Image.Components.URL.imagekit/2` faithfully drops the value rather than approximating it. If you need the same visual contrast across all four providers, ImageKit will be the odd one out.

## Vignette and tint

These two are honest single-CDN features:

* `vignette={0.6}` projects to Cloudinary's `e_vignette:60`. The other three providers drop it.
* `tint="#80a0c0"` projects to imgix's `monochrome=80a0c0`. The other three providers drop it.

```heex
<.image src="/cat.jpg" provider={:cloudinary} vignette={0.6} />
<.image src="/cat.jpg" provider={:imgix} tint="#80a0c0" />
```

`tint` accepts a hex string (`"#aabbcc"` or `"aabbcc"`) or an `[r, g, b]` integer list. Both forms are normalised to `[r, g, b]` before they enter the IR, so the type invariant on `Image.Plug.Pipeline.Ops.Tint.color` (`[non_neg_integer()]`) holds regardless of how the component was called.

## `<.picture>` for content negotiation

Use `<.picture>` when you want the browser to pick the best supported format from a short list:

```heex
<.picture
  src="/photo.jpg"
  provider={:cloudflare}
  formats={[:avif, :webp]}
  width={1200}
  fit={:cover}
/>
```

This emits one `<source type="image/avif" srcset="…">`, one `<source type="image/webp" srcset="…">`, and a fallback `<img>` whose `src` uses the `format=` you set explicitly (or the original format if you didn't). The browser walks the `<source>` rows in order and picks the first one whose MIME type it can decode.

The full transform set (width, height, blur, contrast, etc.) is shared across all rows — only the format differs.

## Pre-computing pipelines without rendering

If you need the URL or pipeline without going through HEEx — for example, in a JSON API response or a job that pre-warms a CDN — call the URL builders directly:

```elixir
alias Image.Components.URL
alias Image.Plug.Pipeline
alias Image.Plug.Pipeline.Ops

pipeline = %Pipeline{
  ops: [%Ops.Resize{width: 600, fit: :cover, gravity: :face, face_zoom: 0.6}],
  output: %Ops.Format{type: :webp, quality: 80}
}

URL.cloudflare(pipeline, source_path: "/cat.jpg", host: "/img")
# => "/img/cdn-cgi/image/width=600,fit=cover,gravity=face,face-zoom=0.6,format=webp,quality=80/cat.jpg"
```

Or build the same pipeline from a flat attribute map via the `@doc false` `Image.Components.build_pipeline` helper:

```elixir
pipeline =
  Image.Components.build_pipeline(%{
    width: 600,
    fit: :cover,
    gravity: :face,
    face_zoom: 0.6,
    format: :webp,
    quality: 80
  })
```

`build_pipeline/1` is what `<.image>` and `<.picture>` use internally. It's hidden from ExDoc because it's not part of the stable public API surface, but it's useful for callers that want the same attr-map → IR translation.

## See also

* The README's feature gap table — what each CDN's URL grammar can carry.
* `Image.Components.URL` — module docs for the four URL builders, including provider semantic differences.
* [`image_plug`'s usage guide](https://hexdocs.pm/image_plug/usage.html) — how to mount the four providers in a Phoenix endpoint or Plug.Router.
* [`image_plug`'s face-aware guide](https://hexdocs.pm/image_plug/face_aware.html) — the seam between `image_plug` and `image_vision` and what happens when `image_vision` is absent.
* [`image_playground`](https://github.com/elixir-image/image_playground) — exercises every transform in this guide live, with sliders.
