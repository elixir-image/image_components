defmodule Image.Component.CDN.Cloudinary do
  @moduledoc """
  Cloudinary CDN adapter for `Image.Component`.

  Builds [Cloudinary delivery URLs](https://cloudinary.com/documentation/transformation_reference)
  from the canonical option keys (`:width`, `:height`, `:fit`,
  `:format`, `:quality`, etc.). Wire-format-compatible with both
  Cloudinary's hosted service and an `image_plug` deployment running
  the `Image.Plug.Provider.Cloudinary` provider.

  ### Selecting

      config :image_components,
        defaults: [
          cdn: :cloudinary,
          host: "res.cloudinary.com",
          account: "demo"
        ]

  Or per-call:

      <.image cdn={:cloudinary} src="sample.jpg" alt="" width={800} url_options={[account: "demo"]} ... />

  ### Required option

  * `:account` — your Cloudinary cloud name. Must be supplied
    either via the application defaults or per-call (typically
    via `:url_options`). Without it the URL is structurally invalid
    against Cloudinary's hosted service.

  ### Differences from the imgix and Cloudflare adapters

  * URL grammar embeds account, resource-type, and delivery in the
    path before the transform stage:
    `/<account>/image/<delivery>/<transforms>/<source>`.

  * Signing parameter is an in-path segment `s--<sig>--` (not a
    query parameter); SHA-256 truncated to 32 url-safe-base64
    characters. There is no per-URL expiry parameter — key rotation
    handles long-term revocation.

  * Web-proxy sources (`src: "https://..."`) automatically select
    `delivery=fetch` and embed the absolute URL into the path
    naturally (no percent-encoding required).

  See `Image.Component.CDN` for the behaviour API and the seam for
  adding additional CDN adapters.
  """

  @behaviour Image.Component.CDN

  alias Image.Component.CDN.Cloudinary.{Signing, URL}

  @impl Image.Component.CDN
  def build_url(source, options) do
    URL.build(source, options)
  end

  @impl Image.Component.CDN
  def sign_url(url, keys, options) do
    Signing.sign(url, keys, options)
  end
end
