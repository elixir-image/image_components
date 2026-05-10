# Image.Components

Phoenix.Component wrappers (`<.image>` and `<.picture>`) that emit URLs in the documented URL grammars of four major image CDNs plus the [IIIF Image API 3.0](https://iiif.io/api/image/3.0/) standard:

* **Cloudflare Images** (`/cdn-cgi/image/<options>/<source>`)
* **Cloudinary** (`/<account>/image/upload/<options>/<source>`)
* **imgix** (`/<source>?<options>`)
* **ImageKit** (`/<endpoint>/tr:<options>/<source>`)
* **IIIF** (`/iiif/3/<id>/<region>/<size>/<rotation>/<quality>.<format>`)

Point the `host=` attribute at your real Cloudflare / Cloudinary / imgix / ImageKit account and the URLs `<.image>` produces hit those services directly. There is no Elixir-side image processing in the request path, no proxy server you have to run, and no operational dependency on the rest of the `elixir-image` libraries — just URL string construction in your render template, exactly like every other Phoenix.Component.

## Use it directly with your CDN account

```heex
<.image
  src="/cat.jpg"
  provider={:cloudflare}
  host="https://imagedelivery.net/<your-account-hash>"
  width={600}
  fit={:cover}
  format={:webp}
  quality={80}
/>
```

That's it — the rendered `<img src="…">` URL is the one Cloudflare Images itself parses and transforms. Same template against any of the four providers; just change `provider=` and `host=`.

## Installation

```elixir
def deps do
  [
    {:image_components, "~> 0.1"}
  ]
end
```

That's the whole runtime requirement. `image_components` brings in `phoenix_live_view` (for the component machinery) and `image_plug` (for the canonical `Pipeline` IR struct that the URL builders consume — image_plug is *not* invoked at runtime, the struct is just a convenient data carrier shared with the server-side library).

If you also want to self-host the image-processing service — for development, for tests, or as your production origin — mount [`image_plug`](https://hex.pm/packages/image_plug) somewhere on your Phoenix endpoint and set `host=` accordingly. See [Local server in dev, native CDN in prod](https://hexdocs.pm/image_components/environments.html) for the recipe. The components don't care whether the URL ends up at the real CDN's edge or at your own `image_plug` mount; both speak the same URL grammar.

## Quick start

In a LiveView or function component:

```elixir
defmodule MyAppWeb.PageLive do
  use MyAppWeb, :live_view
  import Image.Components

  def render(assigns) do
    ~H"""
    <.image
      src="/uploads/cat.jpg"
      provider={:cloudflare}
      width={600}
      fit={:cover}
      format={:webp}
      quality={80}
    />

    <.picture
      src="/uploads/cat.jpg"
      provider={:cloudflare}
      formats={[:avif, :webp]}
      width={600}
    />
    """
  end
end
```

The components render plain HTML (`<img>` and `<picture>`); the only "magic" is that `src=` (or each `<source srcset=>`) is built by `Image.Components.URL.<provider>/2`. There is no JavaScript and no LiveView-specific behaviour.

## Required configuration per provider

Each CDN needs a `provider=` and a `host=`. Two providers also need an account/endpoint segment in the URL path; the components default both to `"demo"` (a public test account on each service) so the quick-start examples Just Work, but you'll override them once you point at your own account.

| Provider | `provider=` | `host=` (your CDN's edge) | Account segment attribute |
| --- | --- | --- | --- |
| **Cloudflare Images** | `:cloudflare` | `"https://imagedelivery.net/<account-hash>"` (hosted form) or `"https://your-zone.example.com"` (zone form) | n/a — the account hash is in the host |
| **Cloudinary** | `:cloudinary` | `"https://res.cloudinary.com"` | `cloudinary_account="<your-cloud-name>"` |
| **imgix** | `:imgix` | `"https://<your-source>.imgix.net"` | n/a — the source is in the host |
| **ImageKit** | `:imagekit` | `"https://ik.imagekit.io"` | `imagekit_endpoint="<your-endpoint>"` |
| **IIIF** | `:iiif` | `"https://iiif.example.org"` (your IIIF server's base) | `iiif_prefix="/iiif/3"` (the version prefix the server publishes; default `"/iiif/3"`) |

A typical app sets these via `Application` config so render templates stay clean:

```elixir
# config/runtime.exs
config :my_app, :image_cdn,
  provider:           :cloudinary,
  host:               System.fetch_env!("CDN_HOST"),
  cloudinary_account: System.fetch_env!("CLOUDINARY_CLOUD_NAME")
```

…and read it in a thin per-app wrapper component:

```elixir
defmodule MyAppWeb.Components.Image do
  use Phoenix.Component
  import Image.Components, only: [image: 1]

  attr :src, :string, required: true
  attr :rest, :global, include: ~w(width height fit gravity dpr face_zoom format
                                    quality blur sharpen brightness contrast
                                    saturation gamma vignette tint alt class srcset
                                    sizes loading decoding)

  def img(assigns) do
    cdn = Application.fetch_env!(:my_app, :image_cdn)
    assigns = assign(assigns,
      provider: cdn[:provider],
      host: cdn[:host],
      cloudinary_account: cdn[:cloudinary_account] || "demo",
      imagekit_endpoint:  cdn[:imagekit_endpoint]  || "demo"
    )

    ~H"""
    <.image
      src={@src}
      provider={@provider}
      host={@host}
      cloudinary_account={@cloudinary_account}
      imagekit_endpoint={@imagekit_endpoint}
      {@rest}
    />
    """
  end
end
```

Then everywhere else in your app:

```heex
<.img src="/cat.jpg" width={600} fit={:cover} alt="A cat" />
```

The full per-environment recipe (different `host=` in dev/test/prod, conditionally mounting `image_plug` for local development) is in the [environments guide](https://hexdocs.pm/image_components/environments.html).

## URLs without rendering

If you only need URLs, skip the components and call the projector directly:

```elixir
alias Image.Components.URL
alias Image.Plug.Pipeline
alias Image.Plug.Pipeline.Ops

pipeline = %Pipeline{
  ops: [%Ops.Resize{width: 600, fit: :cover, gravity: :face}],
  output: %Ops.Format{type: :webp, quality: 80}
}

URL.cloudflare(pipeline, source_path: "/cat.jpg", host: "/img")
# => "/img/cdn-cgi/image/width=600,fit=cover,gravity=face,format=webp,quality=80/cat.jpg"
```

## Provider semantic differences

Adjust effects (`brightness`, `contrast`, `saturation`, `gamma`)
have one IR — multipliers where `1.0` = no change — but the four
CDNs encode them differently:

* **Cloudflare** takes the raw multiplier directly: `contrast=1.4`.
* **Cloudinary** and **imgix** take centred percentages in
  `-100..100`: `e_contrast:40` / `con=40` (both equivalent to
  `1.4`).
* **ImageKit** has no parameterised brightness/contrast/saturation/
  gamma in its URL grammar — only an unparameterised `e-contrast`
  toggle. The IR multiplier cannot be faithfully expressed and is
  silently dropped. No approximation is performed; the resulting
  URL is what ImageKit can carry.

Similarly: `vignette` survives only into Cloudinary
(`e_vignette:N`); `tint` survives only into imgix
(`monochrome=<hex>`). The other CDNs drop these silently.

## Provider feature gaps

| IR op           | Cloudflare    | Cloudinary  | imgix         | ImageKit      | IIIF                  |
| --------------- | ------------- | ----------- | ------------- | ------------- | --------------------- |
| `Resize`        | ✓             | ✓           | ✓             | ✓             | ✓ (`fit: :cover` —)   |
| `Format`        | ✓             | ✓           | ✓             | ✓             | ✓ (`:auto` →fallback) |
| `Adjust`        | ✓ (raw mult.) | ✓ (centred) | ✓ (centred)   | —             | gray only             |
| `Blur`          | ✓             | ✓           | ✓             | ✓             | —                     |
| `Sharpen`       | ✓             | ✓           | ✓             | ✓             | —                     |
| `Vignette`      | —             | ✓           | —             | —             | —                     |
| `Tint`          | —             | —           | ✓ (mono only) | —             | —                     |
| `Rotate`        | ✓             | —           | ✓             | ✓             | ✓ (any 0..360)        |
| `Trim`          | ✓             | —           | ✓             | —             | —                     |
| `Background`    | ✓             | —           | ✓             | ✓             | —                     |
| `face_zoom`     | ✓             | ✓           | —             | ✓             | —                     |
| `Crop`          | —             | —           | —             | —             | ✓                     |
| `Posterize{2}`  | —             | —           | —             | —             | ✓ (→ bitonal)         |

Empty cells = no equivalent in that grammar. **IIIF** is the only entry that actually expresses sub-region cropping in URL form (`region` segment); CDN providers express crop indirectly via fit modes.

## Components

### `<.image>`

Renders a single `<img>` whose `src` is the projected URL.

```heex
<.image
  src="/uploads/cat.jpg"
  provider={:cloudflare}
  host="/img"
  width={600}
  height={400}
  fit={:cover}
  gravity={:face}
  face_zoom={0.6}
  format={:webp}
  quality={80}
  blur={2.5}
  brightness={1.1}
  contrast={1.2}
  alt="A cat"
  class="rounded-lg"
/>
```

See `Image.Components.image/1` for the full attribute reference.

### `<.picture>`

Renders a `<picture>` with one `<source srcset=>` per format in
`:formats` (default `[:avif, :webp]`) plus a fallback `<img>`.

```heex
<.picture
  src="/uploads/cat.jpg"
  provider={:cloudflare}
  formats={[:avif, :webp]}
  width={1200}
  fit={:cover}
/>
```

See `Image.Components.picture/1` for the full attribute reference.

## Adding a new CDN provider

A provider is a single function from `Image.Plug.Pipeline.t()` plus an options keyword list to a URL string. To add a new CDN — say [Bunny.net Image Optimizer](https://bunny.net/optimizer/), or an internal one — write a module with one public function per CDN you support, mirroring `Image.Components.URL`:

```elixir
defmodule MyApp.URL do
  alias Image.Plug.Pipeline
  alias Image.Plug.Pipeline.Ops

  @spec bunny(Pipeline.t(), keyword()) :: String.t()
  def bunny(%Pipeline{} = pipeline, options \\ []) do
    query = pipeline |> bunny_options() |> URI.encode_query()
    source = Keyword.get(options, :source_path, "/sample.jpg")
    host = Keyword.get(options, :host, "")

    if query == "", do: "#{host}#{source}", else: "#{host}#{source}?#{query}"
  end

  defp bunny_options(pipeline) do
    resize = Enum.find(pipeline.ops, &match?(%Ops.Resize{}, &1))
    output = pipeline.output

    []
    |> opt("width",  resize && resize.width)
    |> opt("height", resize && resize.height)
    |> opt("aspect_ratio", resize && resize.fit && bunny_fit(resize.fit))
    |> opt("quality", output && output.quality)
    # …add per-op tokens as you support them.
  end

  defp opt(acc, _key, nil), do: acc
  defp opt(acc, key, value), do: acc ++ [{key, to_string(value)}]

  defp bunny_fit(:cover), do: "1:1"
  defp bunny_fit(_), do: nil
end
```

Then expose it through your own component, or extend the `<.image>` you wrap in your app:

```elixir
defp build_url(:bunny, pipeline, options), do: MyApp.URL.bunny(pipeline, options)
defp build_url(other, pipeline, options), do: apply(Image.Components.URL, other, [pipeline, options])
```

The provider behaviour is *informal* — there is no `@behaviour` to implement. Each builder takes `(pipeline, options)` and returns a string; the components dispatch on the `provider=` atom. Keep your builder in your app's namespace if it's app-specific, or release it as a small companion package that depends on `image_components` for the IR types and adds `<provider>/2` to the surface.

When the new CDN's URL grammar can't faithfully express an IR op, drop it silently — every shipped builder does the same. Don't approximate; the provider you pick should be the contract, and the URL it produces should be the truth of what that CDN can carry.

If your new CDN warrants two-way compatibility (URL parsing as well as URL building) so the in-process `image_plug` can serve it during development, the parser side lives in [`image_plug`](https://hex.pm/packages/image_plug) — see its provider modules for examples of the inverse mapping.

## Guides

* [Usage](https://hexdocs.pm/image_components/usage.html) — `<.image>` and `<.picture>` walk-through, host/mount configuration, face-aware crops, per-CDN encoding of adjust effects, vignette and tint, `<.picture>` content negotiation, pre-computing pipelines.

* [Responsive `<picture>` patterns](https://hexdocs.pm/image_components/responsive.html) — format negotiation, density (1×/2×/3×), width-based `srcset` + `sizes`, art direction with `<source media>`, and how to compose them. Includes worked recipes for each pattern as app-specific wrapper components.

* [IIIF Image API 3.0](https://hexdocs.pm/image_components/iiif.html) — the fifth provider, `:iiif`. URL grammar, the `region=` and `iiif_quality=` IIIF-specific attributes, server-prefix conventions, and the conformance limits IIIF imposes (no effects, no `:cover` fit, no per-channel adjust).

* [Local server in dev, native CDN in prod](https://hexdocs.pm/image_components/environments.html) — recipe for running an in-process `image_plug` in development and test, then pointing at the real Cloudflare / Cloudinary / imgix / ImageKit edge in production.

For source resolution (file vs HTTP vs S3 vs custom), see [`image_plug`'s sources guide](https://hexdocs.pm/image_plug/sources.html).

## Testing

The test suite has three layers, each at a different point on the speed/coverage trade-off.

* **Default suite** (`mix test`) — unit tests for `Image.Components.URL` and `build_pipeline/1`, plus property-based **round-trip tests** that project a generated `Pipeline` to a URL via this library and parse it back via the matching `image_plug` provider. Catches projector/parser drift inside the codebase. Fast (~2 s), no external dependencies. Tagged `:round_trip`.

* **Cross-SDK validation** (`mix test --include cross_sdk`) — for each canonical intent, builds the URL via `Image.Components.URL` AND via the official vendor SDK (Cloudinary, imgix, ImageKit), then compares as token / parameter sets (order-independent, SDK-tracking parameters filtered out). Confirms our URL grammar matches what the vendors themselves emit. Requires Node + an `npm install` in `test/support/cross_sdk/`. Cloudflare is not covered — Cloudflare doesn't ship a first-party URL builder.

* **Live CDN integration** (`mix test --include live_cdn`) — fetches the URL from the real Cloudinary / imgix / ImageKit public demo endpoints and asserts the response is an image of approximately the requested dimensions. Highest-confidence verification; the actual edge service rendering our URLs. Slow (~3 s, network-dependent) and tagged `:live_cdn` so it doesn't run in normal `mix test`. Cloudflare is not covered — no public demo account.

For the cross-SDK suite, install the Node helper deps once:

```sh
cd test/support/cross_sdk && npm install
mix test --include cross_sdk
```

Run all three layers together:

```sh
mix test --include cross_sdk --include live_cdn
```

## Playground

[`image_playground`](https://github.com/elixir-image/image_playground) is a Phoenix LiveView app that drives this library and the four provider mounts in `image_plug`. Drop an image, tweak transforms with sliders, and watch the four CDN URLs and the equivalent HEEx call update live next to a rendered preview.

## License

Apache-2.0.
