# Changelog

All notable changes to this project will be documented in this file. See [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## v0.1.0

Phoenix.Component wrappers and per-CDN URL builders for the [`elixir-image`](https://github.com/elixir-image) ecosystem. Same canonical `Image.Plug.Pipeline` IR drives every URL grammar, so a single attribute set yields equivalent URLs across providers — modulo each CDN's grammar gaps.

Requires `:image_plug` `~> 0.1` and `:phoenix_live_view` `~> 1.1`.

### Features

* `<.image>` — renders an `<img>` whose `src` is projected from the per-transform attribute set onto the chosen CDN's URL grammar.

* `<.picture>` — renders a `<picture>` with one `<source srcset>` per format (default `[:avif, :webp]`) plus a fallback `<img>`.

* `<.iiif>` — IIIF-specific component with three modes: `:static` (single `<img>`), `:tiles` (one `<img>` per tile from `source_width`/`source_height` + `tile_width`/`scale_factor`), and `:viewer` (a `<div>` carrying `data-iiif-*` for an OpenSeadragon / Mirador / Leaflet-IIIF hook).

* URL builders for five providers: `Image.Components.URL.cloudflare/2`, `cloudinary/2`, `imgix/2`, `imagekit/2`, and `iiif/2` (IIIF Image API 3.0, Compliance Level 2).

* `Image.Components.URL.iiif_info_url/1` — builds the canonical IIIF info.json discovery URL, honouring `:host` and `:iiif_prefix`.

* HMAC URL signing via `:sign` (and optional `:sign_expires_at`) on every builder — SHA-256 for Cloudflare/imgix, SHA-1 for ImageKit, base64url path-segment for Cloudinary.

* `region` and `iiif_quality` attributes on `<.image>` / `<.picture>` for IIIF region crops (`:full`, `{:pixels, …}`, `{:percent, …}`) and quality (`:default`, `:color`, `:gray`, `:bitonal`).

### Guides

* `guides/usage.md` — `<.image>` / `<.picture>` walk-through, host/mount config, face-aware crops, per-CDN encoding of adjust effects, content negotiation.

* `guides/responsive.md` — the four responsive-image problems (format, density, width-based `srcset`, art direction) with worked recipes and performance hints.

* `guides/environments.md` — running an in-process `image_plug` in dev/test and pointing at a real CDN edge in production.

* `guides/iiif.md` — IIIF provider walk-through covering URL shape, the per-attribute mapping table, deliberately-dropped concepts, and the `<.iiif>` component's three modes.
