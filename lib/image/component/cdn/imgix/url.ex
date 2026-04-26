defmodule Image.Component.CDN.Imgix.URL do
  @moduledoc """
  Imgix URL builder.

  Translates the canonical option keys (`:width`, `:height`,
  `:fit`, `:format`, `:quality`, etc.) into imgix's wire format
  (`w`, `h`, `fit`, `fm`, `q`, ...) and emits a query-string-
  based URL:

      <origin>/<source>?<options>

  Users pass canonical keys regardless of which CDN the URL
  targets — the adapter knows the wire format. So
  `width: 800, format: :webp, fit: :cover` becomes `?w=800&fm=webp&fit=crop`.
  """

  @doc """
  Builds an imgix-style URL.

  ### Arguments

  * `source` is the source path (e.g. `"/photos/sunset.jpg"`) or
    absolute URL (`"https://assets.example.com/sunset.jpg"`).
    Absolute URLs are percent-encoded into a single path segment
    (imgix's web-proxy convention).

  * `options` is a keyword list. URL-shape options (`:host`,
    `:scheme`, `:mount`, `:signing_keys`, `:signing_expires_at`)
    are popped first; the remainder are translated into imgix
    query-string parameters.

  ### Examples

      iex> Image.Component.CDN.Imgix.URL.build("/photos/sunset.jpg", width: 800, fit: :cover, format: :webp)
      "/photos/sunset.jpg?fit=crop&fm=webp&w=800"

      iex> Image.Component.CDN.Imgix.URL.build("/p.jpg", host: "example.imgix.net", width: 200)
      "https://example.imgix.net/p.jpg?w=200"

  """
  @spec build(String.t(), keyword()) :: String.t()
  def build(source, options \\ []) when is_binary(source) and is_list(options) do
    {host, options} = Keyword.pop(options, :host)
    {scheme, options} = Keyword.pop(options, :scheme, "https")
    {mount, options} = Keyword.pop(options, :mount, "")
    {signing_keys, options} = Keyword.pop(options, :signing_keys)
    {signing_expires_at, options} = Keyword.pop(options, :signing_expires_at)

    query =
      options
      |> Enum.map(&encode_option/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()
      |> Enum.join("&")

    source_segment = normalise_source(source)
    origin = origin(host, scheme)
    mount_prefix = normalise_mount(mount)

    base =
      case query do
        "" -> "#{origin}#{mount_prefix}#{source_segment}"
        _ -> "#{origin}#{mount_prefix}#{source_segment}?#{query}"
      end

    maybe_sign(base, signing_keys, signing_expires_at)
  end

  defp origin(nil, _scheme), do: ""
  defp origin("http://" <> _ = host, _scheme), do: host
  defp origin("https://" <> _ = host, _scheme), do: host
  defp origin(host, scheme) when is_binary(host), do: "#{scheme}://#{host}"

  defp normalise_mount(""), do: ""
  defp normalise_mount(mount), do: "/" <> String.trim(mount, "/")

  # Web-proxy: percent-encode the entire URL into one path segment.
  defp normalise_source("http://" <> _ = url), do: "/" <> URI.encode(url, &URI.char_unreserved?/1)

  defp normalise_source("https://" <> _ = url),
    do: "/" <> URI.encode(url, &URI.char_unreserved?/1)

  defp normalise_source("/" <> _ = path), do: path
  defp normalise_source(other), do: "/" <> other

  defp maybe_sign(url, nil, _expires_at), do: url

  defp maybe_sign(url, [_ | _] = keys, expires_at) do
    {origin, path} = split_origin(url)

    signed_path =
      case expires_at do
        nil -> Image.Component.CDN.Imgix.Signing.sign(path, keys)
        e -> Image.Component.CDN.Imgix.Signing.sign(path, keys, expires_at: e)
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

  # ---------- option encoders ----------

  defp encode_option({:width, n}) when is_integer(n) and n > 0, do: "w=#{n}"
  defp encode_option({:height, n}) when is_integer(n) and n > 0, do: "h=#{n}"
  defp encode_option({:dpr, n}) when is_integer(n) and n > 0, do: "dpr=#{n}"
  defp encode_option({:quality, n}) when is_integer(n) and n in 1..100, do: "q=#{n}"

  defp encode_option({:format, value}) when value in ~w(jpeg webp avif png)a do
    "fm=#{format_to_string(value)}"
  end

  defp encode_option({:format, :auto}), do: "auto=format"
  defp encode_option({:format, :baseline_jpeg}), do: "fm=pjpg"

  defp encode_option({:fit, value}) when value in ~w(contain cover crop pad scale_down squeeze)a do
    "fit=#{fit_to_string(value)}"
  end

  defp encode_option({:gravity, atom}) when is_atom(atom), do: "crop=#{gravity_to_string(atom)}"

  defp encode_option({:gravity, {:xy, x, y}}) when is_number(x) and is_number(y) do
    # Caller must also supply :crop=focalpoint or imgix ignores fp-x/fp-y.
    # We emit both so the URL is self-describing.
    "crop=focalpoint&fp-x=#{x}&fp-y=#{y}"
  end

  defp encode_option({:background, color}) when is_binary(color) do
    "bg=#{String.trim_leading(color, "#")}"
  end

  defp encode_option({:blur, n}) when is_number(n) and n > 0 do
    # Inverse of the server's `sigma = N / 100` mapping. Cap at
    # imgix's documented 0..2000 range.
    "blur=#{trunc(min(n * 100, 2000))}"
  end

  defp encode_option({:sharpen, n}) when is_number(n) and n > 0 do
    # Inverse of `sigma = N / 10`. Cap at 0..100.
    "sharp=#{trunc(min(n * 10, 100))}"
  end

  defp encode_option({:brightness, mult}) when is_number(mult), do: "bri=#{adj(mult)}"
  defp encode_option({:contrast, mult}) when is_number(mult), do: "con=#{adj(mult)}"
  defp encode_option({:saturation, mult}) when is_number(mult), do: "sat=#{adj(mult)}"
  defp encode_option({:gamma, mult}) when is_number(mult), do: "gam=#{adj(mult)}"

  defp encode_option({:rotate, value}) when value in [90, 180, 270], do: "rot=#{value}"

  defp encode_option({:flip, :h}), do: "flip=h"
  defp encode_option({:flip, :v}), do: "flip=v"
  defp encode_option({:flip, :hv}), do: "flip=hv"

  # Unknown option → silently dropped, same as the Cloudflare adapter.
  defp encode_option(_other), do: nil

  defp format_to_string(:jpeg), do: "jpg"
  defp format_to_string(other), do: Atom.to_string(other)

  defp fit_to_string(:contain), do: "clip"
  defp fit_to_string(:cover), do: "crop"
  defp fit_to_string(:crop), do: "crop"
  defp fit_to_string(:pad), do: "fill"
  defp fit_to_string(:scale_down), do: "max"
  defp fit_to_string(:squeeze), do: "scale"

  defp gravity_to_string(:north), do: "top"
  defp gravity_to_string(:south), do: "bottom"
  defp gravity_to_string(:east), do: "right"
  defp gravity_to_string(:west), do: "left"
  defp gravity_to_string(:north_east), do: "top,right"
  defp gravity_to_string(:north_west), do: "top,left"
  defp gravity_to_string(:south_east), do: "bottom,right"
  defp gravity_to_string(:south_west), do: "bottom,left"
  defp gravity_to_string(:face), do: "faces"
  defp gravity_to_string(:auto), do: "entropy"
  defp gravity_to_string(:center), do: "faces"
  defp gravity_to_string(other), do: Atom.to_string(other)

  # Inverse of the server's adjust mapping (`mult = 1.0 + N/100`).
  # `mult = 1.2` → `+20`. Clamped to imgix's -100..100.
  defp adj(mult) do
    n = round((mult - 1.0) * 100)
    n |> max(-100) |> min(100)
  end
end
