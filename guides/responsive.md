# Responsive `<picture>` patterns

Modern responsive images solve four distinct problems, and a single `<picture>` element can address any combination of them. This guide shows how to express each pattern with `Image.Components` — what the library does for free, what you assemble from the URL builders, and when to drop down to writing the HTML by hand.

The four problems:

* **Format negotiation** — serve AVIF to browsers that decode it, WebP to those that don't, JPEG/PNG as the universal fallback.
* **Density selection** — serve a 1×, 2×, or 3× pixel-density variant based on the device's display resolution.
* **Width selection** — serve an image whose pixel width matches the layout slot the image occupies, so a 320 px-wide `<img>` slot doesn't download a 1200 px image.
* **Art direction** — show a different *crop* (not just a different size) at different viewport sizes — e.g. a tight portrait crop on phones, a wide landscape crop on desktop.

Format and density are about the same image at different bitrates. Width is about the same image at different pixel sizes. Art direction is about *different images*. The HTML element you reach for differs by case.

## Pattern 1: Format negotiation (the easy one)

This is what `<.picture>` does for you. Pass `:formats` and the component emits one `<source type="image/X" srcset="…">` per format plus a fallback `<img>`:

```heex
<.picture
  src="/uploads/cat.jpg"
  provider={:cloudflare}
  formats={[:avif, :webp]}
  width={800}
  fit={:cover}
/>
```

Renders to:

```html
<picture>
  <source type="image/avif" srcset="/cdn-cgi/image/width=800,fit=cover,format=avif/uploads/cat.jpg" />
  <source type="image/webp" srcset="/cdn-cgi/image/width=800,fit=cover,format=webp/uploads/cat.jpg" />
  <img src="/cdn-cgi/image/width=800,fit=cover/uploads/cat.jpg" />
</picture>
```

The browser walks the `<source>` rows top-down and serves the first format whose `type` it can decode. Chrome and modern Safari take the AVIF row; older Safari takes WebP; legacy browsers fall through to the fallback `<img>`.

Order matters: put the most aggressive format first (smallest files for browsers that support it), the next-best second, and so on. AVIF before WebP is the conventional order — both render identically when both are supported, but the AVIF byte count is typically 30–50% smaller.

The fallback `<img>` uses whatever you set with `format=` if you set it, otherwise the original encoding. If you don't pass `format=`, browsers that fall through to the fallback get the original (often a JPEG); if you want them to also pick up a transform like `quality=80`, pass `format={:jpeg}` explicitly.

### When `<.picture>` is the wrong choice

If you only want format negotiation *and* you're using `format={:auto}`, you don't need `<picture>` at all — the server does the negotiation via `Vary: Accept`. A bare `<.image src="…" format={:auto}>` is simpler:

```heex
<.image src="/uploads/cat.jpg" provider={:cloudflare} width={800} fit={:cover} format={:auto} />
```

The server reads the `Accept` header on the request and picks AVIF / WebP / JPEG accordingly. This works for any provider whose URL grammar supports `format=auto` (all four ship that). The downside is that the URL is opaque — you can't tell from the markup which format the browser actually got — and CDN caching needs `Vary: Accept` configured correctly (see [`image_plug`'s CDN-origin guide](https://hexdocs.pm/image_plug/cdn_origin.html#vary-accept-and-content-negotiation)).

`<.picture>` is the right choice when you want explicit, inspectable format selection and you don't want to depend on the cache layer respecting `Vary`.

## Pattern 2: Density selection (`1x` / `2x` / `3x`)

For Retina-class displays you want to send a 2× pixel-density variant of the same logical image. The HTML pattern is `srcset` with density descriptors:

```html
<img src="/cat-400.jpg"
     srcset="/cat-400.jpg 1x, /cat-800.jpg 2x, /cat-1200.jpg 3x" />
```

The browser picks based on `window.devicePixelRatio`. The `<img>` element is laid out at its CSS dimensions (`src`'s natural width by default, or whatever `width=` / CSS sets); the URL chosen from `srcset` controls *resolution*, not layout size.

`<.image>` doesn't yet ship a high-level helper for density variants, but the `srcset` attribute passes through via the `:rest` global and you can build the value by calling the URL projector directly:

```elixir
defmodule MyAppWeb.Components.RetinaImage do
  use Phoenix.Component
  import Image.Components, only: [image: 1]

  alias Image.Components.URL
  alias Image.Plug.Pipeline
  alias Image.Plug.Pipeline.Ops

  attr :src, :string, required: true
  attr :width, :integer, required: true
  attr :rest, :global

  def retina(assigns) do
    base = %Pipeline{
      ops: [%Ops.Resize{width: assigns.width, fit: :contain}],
      output: %Ops.Format{type: :auto, quality: 80}
    }
    base_2x = put_in(base.ops, [%Ops.Resize{width: assigns.width * 2, fit: :contain}])
    base_3x = put_in(base.ops, [%Ops.Resize{width: assigns.width * 3, fit: :contain}])

    assigns =
      assign(assigns, :srcset,
        "#{URL.cloudflare(base, source_path: assigns.src)} 1x, " <>
        "#{URL.cloudflare(base_2x, source_path: assigns.src)} 2x, " <>
        "#{URL.cloudflare(base_3x, source_path: assigns.src)} 3x"
      )

    ~H"""
    <.image src={@src} provider={:cloudflare} width={@width} srcset={@srcset} {@rest} />
    """
  end
end
```

Use the wrapper:

```heex
<.retina src="/uploads/cat.jpg" width={400} alt="A cat" />
```

The `width=` you pass is the layout width in CSS pixels; the `srcset` provides 1×, 2×, and 3× resolution variants. The browser picks whichever matches the display.

If you don't want the abstraction layer, write the srcset inline — the URL projector is a plain function call and the result is just a string.

## Pattern 3: Width selection (fluid images with `srcset` + `sizes`)

When the image's layout slot changes width across viewports — e.g. it's full-width on phones but half-width on desktop — the right pattern is `srcset` with width descriptors plus a `sizes` hint:

```html
<img src="/cat-800.jpg"
     srcset="/cat-400.jpg 400w,
             /cat-800.jpg 800w,
             /cat-1200.jpg 1200w,
             /cat-1600.jpg 1600w"
     sizes="(max-width: 768px) 100vw, 50vw" />
```

The browser combines `sizes` (which tells it the image's slot width at the current viewport) with `devicePixelRatio` to compute the ideal pixel width, then picks the closest entry from `srcset`. On a 768 px-wide phone with DPR 2 the ideal is `768 * 2 = 1536 px`, so the `1600w` row wins; on a 1440 px desktop displaying the image at 50vw with DPR 1 the ideal is `720 px`, so the `800w` row wins.

The same wrapper pattern as the density example, with width descriptors instead:

```elixir
defmodule MyAppWeb.Components.FluidImage do
  use Phoenix.Component
  import Image.Components, only: [image: 1]

  alias Image.Components.URL
  alias Image.Plug.Pipeline
  alias Image.Plug.Pipeline.Ops

  @breakpoints [400, 800, 1200, 1600]

  attr :src, :string, required: true
  attr :sizes, :string, required: true
  attr :base_width, :integer, default: 800
  attr :rest, :global

  def fluid(assigns) do
    srcset =
      Enum.map_join(@breakpoints, ", ", fn w ->
        pipeline = %Pipeline{
          ops: [%Ops.Resize{width: w, fit: :contain}],
          output: %Ops.Format{type: :auto, quality: 80}
        }
        "#{URL.cloudflare(pipeline, source_path: assigns.src)} #{w}w"
      end)

    assigns = assign(assigns, srcset: srcset)

    ~H"""
    <.image
      src={@src}
      provider={:cloudflare}
      width={@base_width}
      srcset={@srcset}
      sizes={@sizes}
      {@rest}
    />
    """
  end
end
```

Use it:

```heex
<.fluid
  src="/uploads/cat.jpg"
  sizes="(max-width: 768px) 100vw, 50vw"
  alt="A cat"
/>
```

### Picking breakpoints

`[400, 800, 1200, 1600]` is a reasonable starting set. Cloudinary, imgix, and Cloudflare all recommend powers-close-to-2 spacing (each step roughly doubling) — that gives the browser useful options without over-fragmenting your CDN cache. Five steps is usually enough; go finer than that and the cache fragmentation outweighs the bandwidth savings.

If you serve high-DPR devices commonly, add a 2400w or 3200w step. If your design caps image display width at 600 px, drop the 1200w and 1600w rows.

### `sizes` accuracy matters

The browser trusts `sizes`. If you tell it `(max-width: 768px) 100vw, 50vw` but the image actually occupies `(max-width: 768px) 100vw, 33vw`, you'll over-download. Get `sizes` right or browsers will pick a higher-resolution row than they need.

A common shortcut: when the slot width is fixed across all viewports (e.g. an avatar that's always 64 px), skip width-srcset entirely and use density-srcset (Pattern 2) instead. Width-srcset is for fluid layouts; density-srcset is for fixed layouts.

## Pattern 4: Art direction

Art direction is for when the *image content* should differ across viewports — typically a tighter crop on phones (where there's less room for context) and a wider crop on desktop (where there is). The HTML pattern uses `<source media="…">` inside `<picture>`:

```html
<picture>
  <source media="(max-width: 768px)"
          srcset="/cat-portrait.jpg" />
  <source media="(min-width: 769px)"
          srcset="/cat-landscape.jpg" />
  <img src="/cat-landscape.jpg" alt="A cat" />
</picture>
```

The browser evaluates each `<source>`'s `media` query and uses the first match. The fallback `<img>` runs if no `<source>` matches (rare with sensible queries) or if the browser doesn't understand `<picture>`.

`<.picture>` doesn't currently emit `media` attributes, so for art direction you call the URL builders directly and write the `<picture>` markup yourself:

```heex
<picture>
  <source
    media="(max-width: 768px)"
    srcset={Image.Components.URL.cloudflare(
      %Image.Plug.Pipeline{
        ops: [%Image.Plug.Pipeline.Ops.Resize{
          width: 600, height: 800, fit: :cover, gravity: :face, face_zoom: 0.7
        }],
        output: %Image.Plug.Pipeline.Ops.Format{type: :auto, quality: 80}
      },
      source_path: "/uploads/cat.jpg"
    )}
  />
  <source
    media="(min-width: 769px)"
    srcset={Image.Components.URL.cloudflare(
      %Image.Plug.Pipeline{
        ops: [%Image.Plug.Pipeline.Ops.Resize{
          width: 1600, height: 600, fit: :cover, gravity: :center
        }],
        output: %Image.Plug.Pipeline.Ops.Format{type: :auto, quality: 80}
      },
      source_path: "/uploads/cat.jpg"
    )}
  />
  <.image src="/uploads/cat.jpg" provider={:cloudflare} width={1600} fit={:cover} alt="A cat" />
</picture>
```

That's verbose. If you need art direction more than once, wrap it:

```elixir
defmodule MyAppWeb.Components.HeroImage do
  use Phoenix.Component
  import Image.Components, only: [image: 1]

  alias Image.Components.URL
  alias Image.Plug.Pipeline
  alias Image.Plug.Pipeline.Ops

  attr :src, :string, required: true
  attr :alt, :string, required: true

  def hero(assigns) do
    portrait =
      URL.cloudflare(
        %Pipeline{
          ops: [%Ops.Resize{width: 600, height: 800, fit: :cover, gravity: :face, face_zoom: 0.7}],
          output: %Ops.Format{type: :auto, quality: 80}
        },
        source_path: assigns.src
      )

    landscape =
      URL.cloudflare(
        %Pipeline{
          ops: [%Ops.Resize{width: 1600, height: 600, fit: :cover, gravity: :center}],
          output: %Ops.Format{type: :auto, quality: 80}
        },
        source_path: assigns.src
      )

    assigns = assign(assigns, portrait: portrait, landscape: landscape)

    ~H"""
    <picture>
      <source media="(max-width: 768px)" srcset={@portrait} />
      <source media="(min-width: 769px)" srcset={@landscape} />
      <.image src={@src} provider={:cloudflare} width={1600} fit={:cover} alt={@alt} />
    </picture>
    """
  end
end
```

Use it:

```heex
<.hero src="/uploads/banner.jpg" alt="Hero banner" />
```

The face-aware portrait crop on phones; the centred wide crop on desktop. One source image, two crops, one component.

## Combining patterns

The four patterns compose. The fully-loaded `<picture>` for a hero image might do all three of format negotiation, art direction, and width selection:

```html
<picture>
  <!-- Phone: portrait crop, AVIF -->
  <source media="(max-width: 768px)"
          type="image/avif"
          srcset="/.../portrait-400.avif 400w, /.../portrait-800.avif 800w"
          sizes="100vw" />
  <!-- Phone: portrait crop, WebP -->
  <source media="(max-width: 768px)"
          type="image/webp"
          srcset="/.../portrait-400.webp 400w, /.../portrait-800.webp 800w"
          sizes="100vw" />
  <!-- Desktop: landscape crop, AVIF -->
  <source media="(min-width: 769px)"
          type="image/avif"
          srcset="/.../landscape-1200.avif 1200w, /.../landscape-1600.avif 1600w"
          sizes="100vw" />
  <!-- Desktop: landscape crop, WebP -->
  <source media="(min-width: 769px)"
          type="image/webp"
          srcset="/.../landscape-1200.webp 1200w, /.../landscape-1600.webp 1600w"
          sizes="100vw" />
  <!-- Universal fallback -->
  <img src="/.../landscape-1200.jpg" alt="Hero banner" />
</picture>
```

This is six `<source>` rows for two crops × three formats × N widths each. Unwieldy to write inline; build it with the same wrapper pattern as `HeroImage` above, only with the source URLs computed from a list of formats and widths:

```elixir
defp source_rows(crop_pipeline, src, formats, widths) do
  for format <- formats do
    srcset =
      widths
      |> Enum.map_join(", ", fn w ->
        pipeline = put_format(put_width(crop_pipeline, w), format)
        "#{Image.Components.URL.cloudflare(pipeline, source_path: src)} #{w}w"
      end)

    %{type: "image/#{format}", srcset: srcset}
  end
end
```

…and render the rows with `<source :for={s <- @sources} type={s.type} srcset={s.srcset} sizes="100vw" />`.

This is the point where it's worth stepping back. A six-source `<picture>` typically saves <5% bandwidth over a three-source one (browser already picks the best format and width from a single AVIF row). Pick the patterns that match how your site varies, and don't add complexity for compression gains under 10%.

## Choosing a pattern

| You want… | Use |
|---|---|
| Same image, AVIF/WebP fallback to JPEG | `<.picture formats={[:avif, :webp]}>` |
| Same image, format chosen server-side | `<.image format={:auto}>` (rely on `Vary: Accept`) |
| Same image, 2× variant for Retina | `<.image srcset={"<1x> 1x, <2x> 2x"}>` |
| Same image, sized to layout slot | `<.image srcset={…widths…} sizes={"…"}>` |
| Different crop per breakpoint | Hand-rolled `<picture>` with `<source media>` |
| All of the above | Hand-rolled `<picture>` with sources × formats × widths |

The components are a building block, not a framework. For trivial cases use them as-is; for non-trivial cases, treat them as the leaf and build your own per-app wrapper that emits the markup you need.

## Performance hints

Independent of `<picture>` structure, three `<img>` attributes have outsized impact:

* **`loading="lazy"`** — defer fetch until the image scrolls near the viewport. Apply to anything below-the-fold. Harmful on above-the-fold images (LCP), so the rule is: lazy by default, explicit `loading="eager"` for the hero.

* **`decoding="async"`** — let the browser decode off the main thread. No reason not to use this everywhere; the only downside is a tiny chance of layout flash if you're not also setting `width`/`height` for the layout dimension.

* **`fetchpriority="high"`** — boost the priority of a critical above-the-fold image. Use sparingly; promoting too many images defeats the purpose.

All three pass through via `:rest` on both `<.image>` and `<.picture>`:

```heex
<.image
  src="/uploads/hero.jpg"
  provider={:cloudflare}
  width={1600}
  fit={:cover}
  loading="eager"
  decoding="async"
  fetchpriority="high"
  alt="Hero banner"
/>

<.image
  src="/uploads/thumb.jpg"
  provider={:cloudflare}
  width={400}
  fit={:cover}
  loading="lazy"
  decoding="async"
  alt="Article thumbnail"
/>
```

## Always set `width` and `height`

Whether you use `<.image>` or `<.picture>`, set the layout `width` *and* `height` (in CSS pixels) so the browser reserves the correct space before the image decodes. Without it, you get layout shift as each image loads — bad for users and bad for Core Web Vitals (CLS).

Your `width=` attribute serves two purposes in `<.image>`: it goes into the URL (`/cdn-cgi/image/width=400/…`) and it sets the `<img width="…">` HTML attribute. The second use prevents layout shift; the first ensures the byte payload matches the layout. Don't skip either.

For art-directed `<picture>` cases where the crop's aspect ratio differs across breakpoints, set the dimensions in CSS — `<img>` HTML `width`/`height` describe a single intrinsic ratio, which is wrong for the multi-aspect case.

## Related

* [Usage](https://hexdocs.pm/image_components/usage.html) — the basics of `<.image>` and `<.picture>`.
* [Local server in dev, native CDN in prod](https://hexdocs.pm/image_components/environments.html) — the `host=` knob the recipes here all assume.
* [`image_plug`'s CDN-origin guide](https://hexdocs.pm/image_plug/cdn_origin.html) — caching the URLs your `srcset` rows produce.
* `Image.Components.URL` — the four URL builders the wrappers above call.
