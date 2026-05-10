# Changelog

All notable changes to this project will be documented in this file. See [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

* **IIIF Image API 3.0 provider** — `Image.Components.URL.iiif/2` projects an `Image.Plug.Pipeline` onto the [IIIF Image API 3.0](https://iiif.io/api/image/3.0/) URL grammar, targeting [Compliance Level 2](https://iiif.io/api/image/3.0/compliance/). Five positional URL segments (`{region}/{size}/{rotation}/{quality}.{format}`); identifier percent-encoding; `^` upscale prefix; arbitrary 0..360 rotations; per-segment fall-back to the spec's `full` / `max` / `0` / `default` no-op sentinels.

* **Two new `<.image>` / `<.picture>` attributes** — `region=` (`:full`, `{:pixels, x, y, w, h}`, `{:percent, x, y, w, h}`) and `iiif_quality=` (`:default`, `:color`, `:gray`, `:bitonal`). Plus `iiif_prefix=` (server version prefix; default `"/iiif/3"`) and `iiif_format=` (extension fallback when `format: :auto`; default `:jpeg`).

* **`guides/iiif.md`** — provider walk-through covering URL shape, the conformance-level decision (Compliance 2, API 3.0), the per-attribute mapping table, the deliberately-dropped concepts (`fit: :cover`, effects, vignette, tint, face_zoom, non-grayscale `Adjust`), region/quality/rotation usage, server-prefix conventions for Wellcome / LoC / Cantaloupe, and pre-computing pipelines.

### Tests

* **30 new IIIF unit + property tests** in `test/image/components/iiif_test.exs` — five-segment shape, identifier encoding, all size sub-forms, rotation, quality detection, format extension mapping, conformance-gap drop assertions, and two property tests (segment count invariant + identifier round-trip).

* **7 new live IIIF integration tests** (opt-in via `--include live_iiif`) in `test/image/components/iiif_live_test.exs` — fetches against the IIIF Cookbook reference image at `iiif.io` and against Wellcome Collection's production server, asserts response decode and dimension correctness.

## v0.1.0 — initial release

Phoenix.Component wrappers and per-CDN URL builders for the [`elixir-image`](https://github.com/elixir-image) ecosystem. Same canonical `Image.Plug.Pipeline` IR drives all four CDN URL grammars, so a single attribute set yields four URLs with the same semantics — modulo each CDN's URL-grammar gaps.

Requires `:image_plug` `~> 0.1` and `:phoenix_live_view` `~> 1.1`.

### Components

* `<.image>` — renders a single `<img>` whose `src` is built by projecting the per-transform attribute set onto the chosen CDN's URL grammar.

* `<.picture>` — renders a `<picture>` with one `<source srcset>` row per format (default `[:avif, :webp]`) plus a fallback `<img>`.

Both components accept `width`, `height`, `fit`, `gravity`, `dpr`, `face_zoom`, `format`, `quality`, `blur`, `sharpen`, `brightness`, `contrast`, `saturation`, `gamma`, `vignette`, `tint`, plus arbitrary HTML attributes (passed through via `:rest`). The component renders plain HTML — no JavaScript and no LiveView-specific behaviour.

### URL builders

* `Image.Components.URL.cloudflare/2` — `<host>/cdn-cgi/image/<options>/<source>`.
* `Image.Components.URL.cloudinary/2` — `<host>/<account>/image/upload/<options>/<source>`.
* `Image.Components.URL.imgix/2` — `<host>/<source>?<options>`.
* `Image.Components.URL.imagekit/2` — `<host>/<endpoint>/tr:<options>/<source>`.

Each is the inverse of the corresponding URL parser in `image_plug`, so a Pipeline projected onto a URL parses back to the same Pipeline (modulo per-CDN feature gaps documented below).

### Provider-specific encodings

The four projectors faithfully encode each CDN's actual URL grammar — no approximation, no silent re-mapping:

* **Cloudflare** takes brightness/contrast/saturation/gamma as **raw multipliers** (`contrast=1.4` means ×1.4); `face-zoom=<float>` for face-aware crops.

* **Cloudinary** takes adjust effects as **centred percentages** (`e_contrast:40` ≡ ×1.4); `e_vignette:N` for vignette; `z_<float>` for face-aware zoom (parser added in `image_plug` v0.1.x).

* **imgix** takes adjust effects as **centred percentages** (`con=40` ≡ ×1.4); `monochrome=<hex>` is the only tint analog; no native vignette or face-zoom equivalent.

* **ImageKit** has no parameterised brightness/contrast/saturation/gamma — only an unparameterised `e-contrast` toggle. Adjust multipliers are silently dropped (faithful — the URL grammar can't carry them). `z-<float>` for face-aware zoom.

See the README for the full feature gap table.

### Helpers

* `Image.Components.build_pipeline` (marked `@doc false`) is the public-but-undocumented entry point used by both components, and is useful for callers that want to pre-compute a `Pipeline` from a flat attribute map without rendering.

* Tint colours accept hex strings (`"#aabbcc"` or `"aabbcc"`), already-RGB lists (`[170, 187, 204]`), or are silently dropped if unparseable. The IR invariant is `[r, g, b]` integers; conversion happens once at component-time.

### Test surfaces

The test suite has three layers — see `README.md`'s Testing section for the full story:

* **Default suite** — unit tests + property-based round-trip tests (project to URL, parse back via the matching `image_plug` provider, assert the IR survives the trip). 76 tests / 5 doctests / 7 properties; ~2 s; no external deps. Tagged `:round_trip`.

* **Cross-SDK validation** (opt-in via `--include cross_sdk`) — compares `Image.Components.URL` output against the official Cloudinary, imgix, and ImageKit Node SDKs in `test/support/cross_sdk/`. Catches divergence from what the vendors themselves emit. Cloudflare not covered — no first-party URL builder.

* **Live CDN integration** (opt-in via `--include live_cdn`) — hits the real Cloudinary / imgix / ImageKit public demo endpoints, decodes the response, and asserts dimensions. Highest-confidence verification; one of three edge services rendering our URLs. Cloudflare not covered — no public demo account.

### Guides

* `guides/usage.md` — `<.image>` and `<.picture>` walk-through, request flow diagram, host/mount configuration, face-aware crops, per-CDN encoding of adjust effects, vignette and tint, `<.picture>` content negotiation, pre-computing pipelines.

* `guides/environments.md` — recipe for running an in-process `image_plug` in development and test, then pointing at the real Cloudflare / Cloudinary / imgix / ImageKit edge in production. Covers app-config wiring, conditional router mounting, an app-specific wrapper component, and the `Application.compile_env/3` static-binding alternative.

* `guides/responsive.md` — the four responsive-image problems (format negotiation, density selection, width-based `srcset` + `sizes`, art direction) with worked wrapper-component recipes for each. Plus performance hints (`loading`, `decoding`, `fetchpriority`) and the always-set-`width`-and-`height` rule for layout stability.
