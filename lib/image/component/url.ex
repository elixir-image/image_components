defmodule Image.Component.URL do
  @moduledoc """
  Cloudflare Images URL builder for the responsive-image component.

  Mirrors the [`unpic` library's Cloudflare provider](https://github.com/ascorbic/unpic/blob/main/src/providers/cloudflare.ts).

  Given a source URL or path, builds a request URL with the supplied
  options encoded as the comma-separated `<options>` segment of the
  Cloudflare Images URL grammar:

      <host>/<mount>/cdn-cgi/image/<options>/<source>

  The grammar is defined by [Cloudflare Images](https://developers.cloudflare.com/images/transform-images/transform-via-url/).
  Any service that parses the same grammar can serve the URLs this
  module emits. The companion server-side parser ships in
  [`image_plug`](https://hex.pm/packages/image_plug); other CDNs that
  speak the same grammar (Cloudflare itself, custom Workers
  deployments) work too.

  ### Cross-host setups

  Pass a `:host` option to point at a different deployment than the
  one rendering the LiveView. Mirrors `unpic`'s `domain` option.
  """

  @type option ::
          {:width, pos_integer() | :auto}
          | {:height, pos_integer()}
          | {:fit, :contain | :cover | :crop | :pad | :scale_down | :squeeze}
          | {:gravity, atom() | {:xy, float(), float()}}
          | {:dpr, pos_integer()}
          | {:quality, 1..100 | :high | :"medium-high" | :"medium-low" | :low}
          | {:format, :auto | :avif | :webp | :jpeg | :baseline_jpeg | :png | :json}
          | {:metadata, :copyright | :keep | :none}
          | {:anim, boolean()}
          | {:background, String.t()}
          | {:blur, number()}
          | {:sharpen, number()}
          | {:brightness, number()}
          | {:contrast, number()}
          | {:gamma, number()}
          | {:saturation, number()}
          | {:rotate, 90 | 180 | 270}
          | {:flip, :h | :v | :hv}

  @doc """
  Builds a request URL from a source and a keyword list of options.

  ### Arguments

  * `source` is the source path (e.g. `"/photos/sunset.jpg"`) or
    absolute URL (`"https://assets.example.com/sunset.jpg"`).

  * `options` is a keyword list of Cloudflare options plus URL-shape
    options below.

  ### URL-shape options

  * `:host` — origin to prefix the URL with. Either a bare hostname
    (`"img.example.com"`) or a full origin (`"https://img.example.com"`).
    Defaults to `nil` (root-relative URL). Mirrors unpic's `domain`
    option.

  * `:scheme` — `"http"` or `"https"`. Defaults to `"https"`. Only
    consulted when `:host` is set and is a bare hostname.

  * `:mount` — string path prefix the receiving plug is mounted
    under. Defaults to `""`. Trailing slashes are stripped.

  * `:signing_keys` — non-empty list of HMAC secret strings. When
    set, the URL is signed via `Image.Component.Signing.sign/3`
    and `?sig=<hex>` is appended. Use this when your `Image.Plug`
    deployment requires signed URLs.

  * `:signing_expires_at` — `DateTime` or unix-seconds. When set
    alongside `:signing_keys`, the signed URL also carries an
    `?exp=<unix-seconds>` parameter that the back-end verifier
    rejects after the given time.

  ### Cloudflare options

  Every key in `t:option/0` — encoded into the `<options>` segment,
  comma-separated. Order is canonicalised so that two callers that
  supply the same options in different orders produce identical
  URLs (cache-friendly).

  ### Returns

  * A URL string suitable for use as `<img src>`, `<source srcset>`,
    or `<picture>` source attributes.

  ### Examples

      iex> Image.Component.URL.build("/photos/sunset.jpg", width: 800, fit: :cover, format: :webp)
      "/cdn-cgi/image/fit=cover,format=webp,width=800/photos/sunset.jpg"

      iex> Image.Component.URL.build("/photos/sunset.jpg", mount: "/img", width: 400)
      "/img/cdn-cgi/image/width=400/photos/sunset.jpg"

      iex> Image.Component.URL.build("/photos/sunset.jpg",
      ...>   host: "img.example.com",
      ...>   width: 200
      ...> )
      "https://img.example.com/cdn-cgi/image/width=200/photos/sunset.jpg"

  """
  @spec build(String.t(), keyword()) :: String.t()
  def build(source, options \\ []) when is_binary(source) and is_list(options) do
    {host, options} = Keyword.pop(options, :host)
    {scheme, options} = Keyword.pop(options, :scheme, "https")
    {mount, options} = Keyword.pop(options, :mount, "")
    {signing_keys, options} = Keyword.pop(options, :signing_keys)
    {signing_expires_at, options} = Keyword.pop(options, :signing_expires_at)

    options_segment =
      options
      |> Enum.map(&encode_option/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()
      |> Enum.join(",")

    source_segment = normalise_source(source)
    origin = origin(host, scheme)
    mount_prefix = normalise_mount(mount)

    base =
      case options_segment do
        "" -> "#{origin}#{mount_prefix}#{source_segment}"
        _ -> "#{origin}#{mount_prefix}/cdn-cgi/image/#{options_segment}/#{strip_leading_slash(source_segment)}"
      end

    maybe_sign(base, signing_keys, signing_expires_at)
  end

  defp maybe_sign(url, nil, _expires_at), do: url

  defp maybe_sign(url, [_ | _] = keys, expires_at) do
    # The back-end's `Image.Plug.Signing` verifies against the
    # request path-and-query only (no origin). Strip the origin
    # before signing so the wire format matches both whether the
    # component included a `:host` or not.
    {origin, path} = split_origin(url)

    signed_path =
      case expires_at do
        nil -> Image.Component.Signing.sign(path, keys)
        e -> Image.Component.Signing.sign(path, keys, expires_at: e)
      end

    origin <> signed_path
  end

  defp split_origin("http://" <> _ = url), do: split_origin_at_path(url)
  defp split_origin("https://" <> _ = url), do: split_origin_at_path(url)
  defp split_origin(path), do: {"", path}

  defp split_origin_at_path(url) do
    case String.split(url, "/", parts: 4) do
      [scheme, "", host, rest] -> {scheme <> "//" <> host, "/" <> rest}
      _ -> {"", url}
    end
  end

  defp origin(nil, _scheme), do: ""

  defp origin("http://" <> _ = host, _scheme), do: host
  defp origin("https://" <> _ = host, _scheme), do: host

  defp origin(host, scheme) when is_binary(host), do: "#{scheme}://#{host}"

  defp normalise_mount(""), do: ""
  defp normalise_mount(mount), do: "/" <> String.trim(mount, "/")

  defp normalise_source("http://" <> _ = url), do: url
  defp normalise_source("https://" <> _ = url), do: url
  defp normalise_source("/" <> _ = path), do: path
  defp normalise_source(other), do: "/" <> other

  defp strip_leading_slash("/" <> rest), do: rest
  defp strip_leading_slash(other), do: other

  # ---- option encoders ----

  defp encode_option({:width, :auto}), do: "width=auto"
  defp encode_option({:width, value}) when is_integer(value) and value > 0, do: "width=#{value}"
  defp encode_option({:height, value}) when is_integer(value) and value > 0, do: "height=#{value}"

  defp encode_option({:fit, value})
       when value in ~w(contain cover crop pad scale_down squeeze)a do
    "fit=#{fit_to_string(value)}"
  end

  defp encode_option({:dpr, value}) when is_integer(value) and value > 0, do: "dpr=#{value}"

  defp encode_option({:quality, value}) when is_integer(value) and value in 1..100,
    do: "quality=#{value}"

  defp encode_option({:quality, named}) when is_atom(named), do: "quality=#{named}"

  defp encode_option({:format, value})
       when value in ~w(auto avif webp jpeg baseline_jpeg png json)a do
    "format=#{format_to_string(value)}"
  end

  defp encode_option({:metadata, value}) when value in ~w(copyright keep none)a do
    "metadata=#{value}"
  end

  defp encode_option({:anim, true}), do: "anim=true"
  defp encode_option({:anim, false}), do: "anim=false"

  defp encode_option({:background, color}) when is_binary(color), do: "background=#{color}"

  defp encode_option({:blur, n}) when is_number(n) and n > 0, do: "blur=#{n}"
  defp encode_option({:sharpen, n}) when is_number(n) and n > 0, do: "sharpen=#{n}"
  defp encode_option({:brightness, n}) when is_number(n), do: "brightness=#{n}"
  defp encode_option({:contrast, n}) when is_number(n), do: "contrast=#{n}"
  defp encode_option({:gamma, n}) when is_number(n), do: "gamma=#{n}"
  defp encode_option({:saturation, n}) when is_number(n), do: "saturation=#{n}"

  defp encode_option({:rotate, value}) when value in [90, 180, 270], do: "rotate=#{value}"

  defp encode_option({:flip, :h}), do: "flip=h"
  defp encode_option({:flip, :v}), do: "flip=v"
  defp encode_option({:flip, :hv}), do: "flip=hv"

  defp encode_option({:gravity, named}) when is_atom(named) do
    "gravity=#{gravity_to_string(named)}"
  end

  defp encode_option({:gravity, {:xy, x, y}}) when is_number(x) and is_number(y) do
    "gravity=#{x}x#{y}"
  end

  defp encode_option(_other), do: nil

  defp fit_to_string(:scale_down), do: "scale-down"
  defp fit_to_string(other), do: Atom.to_string(other)

  defp format_to_string(:baseline_jpeg), do: "baseline-jpeg"
  defp format_to_string(other), do: Atom.to_string(other)

  defp gravity_to_string(:north_east), do: "northeast"
  defp gravity_to_string(:north_west), do: "northwest"
  defp gravity_to_string(:south_east), do: "southeast"
  defp gravity_to_string(:south_west), do: "southwest"
  defp gravity_to_string(other), do: Atom.to_string(other)
end
