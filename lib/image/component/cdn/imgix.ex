defmodule Image.Component.CDN.Imgix do
  @moduledoc """
  Imgix CDN adapter for `Image.Component`.

  Builds [imgix-grammar URLs](https://docs.imgix.com/en/latest/apis/rendering)
  from the canonical option keys (`:width`, `:height`, `:fit`,
  `:format`, `:quality`, etc.). Wire-format-compatible with both
  imgix's hosted service and an `image_plug` deployment running
  the `Image.Plug.Provider.Imgix` provider.

  ### Selecting

      config :image_components,
        defaults: [
          cdn: :imgix,
          host: "example.imgix.net"
        ]

  Or per-call:

      <.image cdn={:imgix} src="/photos/sunset.jpg" alt="" width={800} ... />

  ### Differences from the Cloudflare adapter

  * URL grammar is query-string-based (`?w=800&fit=crop&fm=webp`)
    rather than path-segment-based (`/cdn-cgi/image/.../`).

  * Signing parameter is `s=<hex>` (not `sig=`) and `expires=<unix>`
    (not `exp=`); HMAC payload prepends the secret to the path-
    and-query.

  * Web-proxy sources (`src: "https://..."`) are percent-encoded
    into a single path segment, per imgix's convention.

  See `Image.Component.CDN` for the behaviour API and the seam
  for adding additional CDN adapters.
  """

  @behaviour Image.Component.CDN

  alias Image.Component.CDN.Imgix.{Signing, URL}

  @impl Image.Component.CDN
  def build_url(source, options) do
    URL.build(source, options)
  end

  @impl Image.Component.CDN
  def sign_url(url, keys, options) do
    Signing.sign(url, keys, options)
  end
end
