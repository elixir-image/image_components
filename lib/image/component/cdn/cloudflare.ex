defmodule Image.Component.CDN.Cloudflare do
  @moduledoc """
  Cloudflare Images URL adapter for `Image.Component`.

  The default adapter. Builds URLs against the
  [Cloudflare Images URL grammar](https://developers.cloudflare.com/images/transform-images/transform-via-url/)
  (`/cdn-cgi/image/<options>/<source>`) and signs them via the
  Cloudflare-compatible HMAC-SHA256 scheme using `?sig=<hex>` and
  `?exp=<unix-seconds>` query parameters — the same parameter
  names Cloudflare's hosted Images service uses for signed URLs.

  Wrap-only — delegates to `Image.Component.URL` and
  `Image.Component.Signing`. Exists as a module so the `:cdn`
  config seam is uniform across built-in and custom adapters.
  """

  @behaviour Image.Component.CDN

  @impl Image.Component.CDN
  def build_url(source, options) do
    Image.Component.URL.build(source, options)
  end

  @impl Image.Component.CDN
  def sign_url(url, keys, options) do
    Image.Component.Signing.sign(url, keys, options)
  end
end
