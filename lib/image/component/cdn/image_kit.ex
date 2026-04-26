defmodule Image.Component.CDN.ImageKit do
  @moduledoc """
  ImageKit CDN adapter for `Image.Component`.

  Builds [ImageKit URLs](https://imagekit.io/docs/transformations)
  from the canonical option keys (`:width`, `:height`, `:fit`,
  `:format`, `:quality`, etc.). Wire-format-compatible with both
  ImageKit's hosted service and an `image_plug` deployment running
  the `Image.Plug.Provider.ImageKit` provider.

  ### Selecting

      config :image_components,
        defaults: [
          cdn: :image_kit,
          host: "ik.imagekit.io",
          url_options: [endpoint: "your_imagekit_id"]
        ]

  Or per-call:

      <.image cdn={:image_kit} src="/sample.jpg" alt="" width={800} ... />

  ### Differences from the other adapters

  * URL grammar uses a `tr:` path-prefix segment (`/<endpoint>/tr:<transforms>/<source>`)
    rather than path components or query strings. ImageKit also
    accepts a `?tr=<transforms>` query-string form on inbound; this
    adapter emits the path-prefix form.

  * Signing parameter is `ik-s=<hex>` and `ik-t=<unix-seconds>`;
    HMAC-SHA1 (matching ImageKit's documented default).

  See `Image.Component.CDN` for the behaviour API and the seam for
  adding additional CDN adapters.
  """

  @behaviour Image.Component.CDN

  alias Image.Component.CDN.ImageKit.{Signing, URL}

  @impl Image.Component.CDN
  def build_url(source, options) do
    URL.build(source, options)
  end

  @impl Image.Component.CDN
  def sign_url(url, keys, options) do
    Signing.sign(url, keys, options)
  end
end
