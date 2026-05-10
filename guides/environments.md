# Local server in dev, native CDN in prod

`<.image>` and `<.picture>` produce URLs in the documented URL grammar of the CDN you target. In production you typically point them straight at the real Cloudflare Images / Cloudinary / imgix / ImageKit edge — no Elixir-side processing, no proxy server. The components are doing nothing more than building a `src=` string the CDN understands.

For development and test, that direct-to-CDN mode is often inconvenient: you don't want every preview render to hit the production account, you don't want to upload local fixture images to a remote bucket, and you don't want to depend on the network. The recommended workaround is to run an in-process [`image_plug`](https://hex.pm/packages/image_plug) server in dev and test only — it speaks the same URL grammars, so the component templates don't change. This guide shows the recipe.

## The two knobs that change

The `host=` and `provider=` attributes are the only things that need to vary between environments. Everything else — the per-transform attributes (`width`, `fit`, `gravity`, …), the source path, the rendered HTML — stays identical. The point of the canonical IR is that the same component call works against any of the four CDNs.

```heex
<%!-- Same call, different host. --%>
<.image src="/uploads/cat.jpg" provider={:cloudflare} host="/img" width={600} />
<.image src="/uploads/cat.jpg" provider={:cloudflare} host="https://images.example.com" width={600} />
```

The first form points at an in-process `image_plug` mounted at `/img` on the same Phoenix endpoint. The second points at Cloudflare Images at `images.example.com`. Both URLs resolve to the same transformed image.

## The recipe

### 1. Configure the CDN per environment

In `config/config.exs`, declare a single `:image_cdn` key with whatever default is most useful for your dev workflow:

```elixir
# config/config.exs
import Config

config :my_app, :image_cdn,
  provider: :cloudflare,
  host: ""           # in-process image_plug mounted at the app root
```

Then override in the environment-specific config files where the value differs:

```elixir
# config/dev.exs
config :my_app, :image_cdn,
  provider: :cloudflare,
  host: "/img"       # in-process image_plug at /img on the dev endpoint

# config/test.exs
config :my_app, :image_cdn,
  provider: :cloudflare,
  host: "/img"       # same in-process mount; tests don't hit the network

# config/runtime.exs (production)
config :my_app, :image_cdn,
  provider: String.to_existing_atom(System.fetch_env!("IMAGE_PROVIDER")),
  host: System.fetch_env!("IMAGE_HOST")
```

Pulling the prod values from env vars (rather than baking them into a compiled config) means the same release artifact can be deployed against staging and production with different CDNs.

### 2. Mount `image_plug` only in dev and test

The in-process server is a development convenience; in production you usually want the real CDN to do the work, so the route doesn't need to exist:

```elixir
# lib/my_app_web/router.ex
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  # ... pipelines, scopes, lives, etc.

  if Application.compile_env(:my_app, :image_plug_local?, false) do
    forward "/img", Image.Plug,
      provider: {Image.Plug.Provider.Cloudflare, []},
      source_resolver:
        {Image.Plug.SourceResolver.File, root: Path.expand("priv/static/uploads")}
  end
end
```

Plus the matching compile-env flag:

```elixir
# config/dev.exs and config/test.exs
config :my_app, :image_plug_local?, true

# config/prod.exs (or just don't set it)
config :my_app, :image_plug_local?, false
```

`Application.compile_env/3` is evaluated at compile time, so the forward route is conditionally included in the compiled router — no runtime cost in prod, no risk of accidentally serving image transforms from the production node.

For a deeper look at source resolution — including the directory layout, the `Composite` dispatcher for serving file/HTTP/hosted sources from one mount, and how to add an S3 resolver — see [`image_plug`'s sources guide](https://hexdocs.pm/image_plug/sources.html).

### 3. Wrap `<.image>` with your app's defaults

Reading the CDN config in every render is noisy. Wrap the component once:

```elixir
defmodule MyAppWeb.Components.Image do
  use Phoenix.Component
  import Image.Components, only: [image: 1, picture: 1]

  attr :src, :string, required: true
  attr :rest, :global,
    include: ~w(width height fit gravity dpr face_zoom format quality
                blur sharpen brightness contrast saturation gamma
                vignette tint alt class srcset sizes loading decoding)

  def img(assigns) do
    cdn = Application.get_env(:my_app, :image_cdn, [])
    assigns = assign(assigns, provider: cdn[:provider], host: cdn[:host] || "")

    ~H"""
    <.image src={@src} provider={@provider} host={@host} {@rest} />
    """
  end

  attr :src, :string, required: true
  attr :formats, :list, default: [:avif, :webp]
  attr :rest, :global,
    include: ~w(width height fit gravity dpr face_zoom format quality
                blur sharpen brightness contrast saturation gamma
                vignette tint alt class loading decoding)

  def pic(assigns) do
    cdn = Application.get_env(:my_app, :image_cdn, [])
    assigns = assign(assigns, provider: cdn[:provider], host: cdn[:host] || "")

    ~H"""
    <.picture src={@src} provider={@provider} host={@host} formats={@formats} {@rest} />
    """
  end
end
```

Then use it everywhere:

```heex
<.img src="/uploads/cat.jpg" width={600} fit={:cover} alt="A cat" />
<.pic src="/uploads/cat.jpg" formats={[:avif, :webp]} width={1200} />
```

The CDN just changes per environment; the templates stay clean.

## Switching provider per environment

Sometimes you want different *providers* in different environments — for example `:cloudflare` in production (because that's where you host) but `:imgix` for local dev (because the dev source lives on an imgix-fronted bucket and signing is cheaper there). The same recipe handles it:

```elixir
# config/dev.exs
config :my_app, :image_cdn, provider: :imgix, host: "https://my-source.imgix.net"

# config/runtime.exs
config :my_app, :image_cdn, provider: :cloudflare, host: "https://images.example.com"
```

Note that the URL paths emitted by the four projectors are different — `/cdn-cgi/image/...` vs `/<account>/image/upload/...` — so the *URLs* differ between environments, but the *rendered transforms* match. If you have absolute URLs hard-coded somewhere (e.g. cached HTML in a CDN), switching providers will invalidate them; switching only the host keeps URL paths stable.

## Static binding (the "no app config" alternative)

If you don't want runtime config at all and you're happy to bake the CDN into the compiled module, use `Application.compile_env/3` instead of `Application.get_env/3` in the wrapper:

```elixir
defmodule MyAppWeb.Components.Image do
  use Phoenix.Component
  import Image.Components, only: [image: 1]

  @cdn Application.compile_env!(:my_app, :image_cdn)

  attr :src, :string, required: true
  attr :rest, :global

  def img(assigns) do
    assigns = assign(assigns, provider: @cdn[:provider], host: @cdn[:host])

    ~H"""
    <.image src={@src} provider={@provider} host={@host} {@rest} />
    """
  end
end
```

This requires a release rebuild to change the CDN, but eliminates the per-render `Application.get_env/3` lookup. For most apps the runtime form is simpler and the lookup cost is negligible.

## Why use the same provider in dev and prod?

Because the URL grammar then matches. Cloudflare's `/cdn-cgi/image/width=600/cat.jpg` is the same string whether served by your local `image_plug` or by the real Cloudflare edge. The browser can cache it, the URL appears in your HTML the same way, and switching environments doesn't shake out subtle URL-shape bugs that only appear in production.

The provider you pick in dev should usually be the provider you pay for in prod, even if they accept very different feature sets — the in-process `image_plug` faithfully implements each provider's URL grammar, so you'll see the same `:contrast=1.4` is dropped on ImageKit (per the gap table) whether you're hitting localhost or the real edge.

## Production extras worth knowing

* **Signed URLs.** Cloudflare hosted Images and Cloudinary signed delivery use HMAC signing that the URL projectors don't currently emit. If you need signed URLs in production, build them with the provider's signing helpers (`Image.Plug.Provider.Cloudflare.Signing`, `Image.Plug.Provider.Cloudinary.Signing`) and pass the signed URL as the `src=` attribute (skip the projector's host machinery for those URLs).

* **CDN account in `cloudinary_account` / `imagekit_endpoint`.** If your Cloudinary cloud-name or ImageKit endpoint is not `"demo"`, set the per-CDN segment via the component attrs of the same name — or bake them into your wrapper.

* **TLS port in `URL_PORT` / `URL_SCHEME`.** When `image_plug` runs on the same Phoenix endpoint as your app and that endpoint is behind a TLS terminator, set those env vars in your release config (see the runtime.exs of `image_playground` for an example).

## Related

* [`image_plug`'s sources guide](https://hexdocs.pm/image_plug/sources.html) — how source resolution actually works, the default file resolver, the HTTP resolver, and how to add a custom one (S3 example).
* [`image_plug`'s usage guide](https://hexdocs.pm/image_plug/usage.html) — the full mount story.
* `Image.Components.URL` — the four URL builders this guide configures around.
