defmodule Image.Component.CDN.ImageKit.URL do
  @moduledoc """
  ImageKit URL builder.

  Translates the canonical option keys (`:width`, `:height`, `:fit`,
  `:format`, `:quality`, etc.) into ImageKit's wire format (`w-`,
  `h-`, `c-`, `f-`, `q-`, ...) and emits the path-prefix form by
  default:

      <origin>/<endpoint>/tr:<transforms>/<source>

  Users pass canonical keys regardless of which CDN the URL targets.
  So `width: 800, format: :webp, fit: :cover` becomes
  `tr:w-800,c-extract,f-webp` (`:cover` maps to `c-extract` plus a
  default centre focus).

  ### Optional configuration

  * `:endpoint` — additional path segment between the host and the
    `tr:` prefix. ImageKit URLs commonly include a per-account id
    (e.g. `/your_imagekit_id/`). Defaults to `""`.
  """

  @doc """
  Builds an ImageKit-style URL.

  ### Arguments

  * `source` is the source path (e.g. `"/photos/sunset.jpg"`) or an
    absolute URL (`"https://assets.example.com/sunset.jpg"`).

  * `options` is a keyword list. URL-shape options (`:host`,
    `:scheme`, `:mount`, `:endpoint`, `:signing_keys`,
    `:signing_expires_at`) are popped first; the remainder are
    translated into ImageKit transform parameters.

  ### Examples

      iex> Image.Component.CDN.ImageKit.URL.build("/photos/sunset.jpg", width: 800, fit: :cover, format: :webp)
      "/tr:c-extract,f-webp,w-800/photos/sunset.jpg"

      iex> Image.Component.CDN.ImageKit.URL.build("/p.jpg", host: "ik.imagekit.io", endpoint: "your_id", width: 200)
      "https://ik.imagekit.io/your_id/tr:w-200/p.jpg"

  """
  @spec build(String.t(), keyword()) :: String.t()
  def build(source, options \\ []) when is_binary(source) and is_list(options) do
    {host, options} = Keyword.pop(options, :host)
    {scheme, options} = Keyword.pop(options, :scheme, "https")
    {mount, options} = Keyword.pop(options, :mount, "")
    {endpoint, options} = Keyword.pop(options, :endpoint, "")
    {signing_keys, options} = Keyword.pop(options, :signing_keys)
    {signing_expires_at, options} = Keyword.pop(options, :signing_expires_at)

    transforms =
      options
      |> Enum.map(&encode_option/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()
      |> Enum.join(",")

    source_segment = normalise_source(source)
    origin = origin(host, scheme)
    mount_prefix = normalise_path_segment(mount)
    endpoint_prefix = normalise_path_segment(endpoint)

    base =
      case transforms do
        "" -> "#{origin}#{mount_prefix}#{endpoint_prefix}#{source_segment}"
        _ -> "#{origin}#{mount_prefix}#{endpoint_prefix}/tr:#{transforms}#{source_segment}"
      end

    maybe_sign(base, signing_keys, signing_expires_at)
  end

  defp origin(nil, _scheme), do: ""
  defp origin("http://" <> _ = host, _scheme), do: host
  defp origin("https://" <> _ = host, _scheme), do: host
  defp origin(host, scheme) when is_binary(host), do: "#{scheme}://#{host}"

  defp normalise_path_segment(""), do: ""
  defp normalise_path_segment(value), do: "/" <> String.trim(value, "/")

  # Web-proxy: ImageKit accepts absolute URLs verbatim under its
  # remote-image endpoint; we keep them as-is.
  defp normalise_source("http://" <> _ = url), do: "/" <> url
  defp normalise_source("https://" <> _ = url), do: "/" <> url
  defp normalise_source("/" <> _ = path), do: path
  defp normalise_source(other), do: "/" <> other

  defp maybe_sign(url, nil, _expires_at), do: url

  defp maybe_sign(url, [_ | _] = keys, expires_at) do
    {origin, path} = split_origin(url)

    signed_path =
      case expires_at do
        nil -> Image.Component.CDN.ImageKit.Signing.sign(path, keys)
        e -> Image.Component.CDN.ImageKit.Signing.sign(path, keys, expires_at: e)
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

  defp encode_option({:width, n}) when is_integer(n) and n > 0, do: "w-#{n}"
  defp encode_option({:height, n}) when is_integer(n) and n > 0, do: "h-#{n}"
  defp encode_option({:dpr, n}) when is_integer(n) and n > 0, do: "dpr-#{n}"
  defp encode_option({:quality, n}) when is_integer(n) and n in 1..100, do: "q-#{n}"

  defp encode_option({:format, value}) when value in ~w(jpeg webp avif png auto)a do
    "f-#{format_to_string(value)}"
  end

  defp encode_option({:fit, value}) when value in ~w(contain cover crop pad scale_down squeeze)a do
    "c-#{fit_to_string(value)}"
  end

  defp encode_option({:gravity, atom}) when is_atom(atom), do: "fo-#{gravity_to_string(atom)}"

  defp encode_option({:gravity, {:xy, x, y}}) when is_number(x) and is_number(y) do
    "fo-custom,x-#{x},y-#{y}"
  end

  defp encode_option({:background, color}) when is_binary(color) do
    "bg-#{String.trim_leading(color, "#")}"
  end

  defp encode_option({:blur, n}) when is_number(n) and n > 0 do
    # Inverse of the server's `sigma = N / 100`. Cap at 0..2000.
    "e-blur-#{trunc(min(n * 100, 2000))}"
  end

  defp encode_option({:sharpen, n}) when is_number(n) and n > 0 do
    "e-sharpen-#{trunc(min(n * 10, 100))}"
  end

  defp encode_option({:rotate, value}) when value in [90, 180, 270], do: "rt-#{value}"

  # Unknown option → silently dropped.
  defp encode_option(_other), do: nil

  defp format_to_string(:jpeg), do: "jpg"
  defp format_to_string(other), do: Atom.to_string(other)

  defp fit_to_string(:contain), do: "maintain_ratio"
  defp fit_to_string(:cover), do: "extract"
  defp fit_to_string(:crop), do: "extract"
  defp fit_to_string(:pad), do: "pad_resize"
  defp fit_to_string(:scale_down), do: "at_max"
  defp fit_to_string(:squeeze), do: "force"

  defp gravity_to_string(:north), do: "top"
  defp gravity_to_string(:south), do: "bottom"
  defp gravity_to_string(:east), do: "right"
  defp gravity_to_string(:west), do: "left"
  defp gravity_to_string(:north_east), do: "top_right"
  defp gravity_to_string(:north_west), do: "top_left"
  defp gravity_to_string(:south_east), do: "bottom_right"
  defp gravity_to_string(:south_west), do: "bottom_left"
  defp gravity_to_string(:face), do: "face"
  defp gravity_to_string(:auto), do: "auto"
  defp gravity_to_string(:center), do: "center"
  defp gravity_to_string(other), do: Atom.to_string(other)
end
