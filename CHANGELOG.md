# Changelog

All notable changes to this project will be documented in this file. See [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## v0.1.0 — initial release

### Highlights

A Phoenix LiveView responsive-image component, with:

* `Image.Component.image/1` — emits `<img srcset sizes>` (or a `<picture type>` for format fallback) with the right performance attributes for LCP and CLS prevention.

* `Image.Component.Picture.picture/1` — emits a `<picture media>` for art direction (different crops/aspect ratios per breakpoint).

* Three layout modes (`:fixed | :constrained | :full_width`) mirroring [`@unpic/core`](https://github.com/ascorbic/unpic-img), with the right inline CSS to reserve layout space and prevent CLS.

* Both width-descriptor (`Nw`) and density-descriptor (`Nx`) srcset flavours, picked automatically from the layout mode.

* Builds URLs against the [Cloudflare Images URL grammar](https://developers.cloudflare.com/images/transform-images/transform-via-url/), so the same component works against [`image_plug`](https://hex.pm/packages/image_plug), Cloudflare's hosted Images service, or any custom Workers deployment that speaks the same grammar.

* `:host` option for cross-host CDN setups (mirrors unpic's `domain`).

* Signed URLs via `:signing_keys` and `:signing_expires_at` attrs, backed by `Image.Component.Signing`. Wire-format-compatible with `Image.Plug.Signing` and Cloudflare's hosted Images service (same `sig`/`exp` parameter names, same HMAC-SHA256 algorithm).

* `Application.get_env(:image_components, :defaults)` consulted for every per-call attr, enabling per-environment configuration (dev → local image_plug, prod → Cloudflare). Per-call attrs win when explicitly set.

* `Image.Component.CDN` behaviour with `:cloudflare` default; pluggable seam for adding non-Cloudflare CDN URL grammars in the future.

See [the README](https://hexdocs.pm/image_components/readme.html) and the [user guide](https://hexdocs.pm/image_components/usage.html) for setup, layout-mode reference, performance attributes, and signed-URL integration.
