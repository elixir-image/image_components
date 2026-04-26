defmodule Image.Component.CDN.Cloudinary.URL do
  @moduledoc """
  Cloudinary URL builder.

  Translates the canonical option keys (`:width`, `:height`, `:fit`,
  `:format`, `:quality`, etc.) into Cloudinary's wire format (`w_`,
  `h_`, `c_`, `f_`, `q_`, ...) and emits a path-segment-based URL:

      <origin>/<account>/<resource-type>/<delivery>/<transforms>/<source>

  Users pass canonical keys regardless of which CDN the URL targets.
  So `width: 800, format: :webp, fit: :cover` becomes
  `w_800,c_fill,f_webp`.

  ### Required configuration

  * `:account` — your Cloudinary cloud name (e.g. `"demo"`). Either
    pass per-call or set it as a default via
    `Application.get_env(:image_components, :defaults)`.

  ### Optional configuration

  * `:resource_type` — defaults to `"image"`. Other values
    (`"video"`, `"raw"`) are passed through verbatim.

  * `:delivery` — defaults to `"upload"` for `:path` sources and
    `"fetch"` for absolute http(s) sources.
  """

  @doc """
  Builds a Cloudinary-style URL.

  ### Arguments

  * `source` is the source public-id (e.g. `"sample.jpg"` or
    `"folder/photo.png"`) or an absolute URL
    (`"https://assets.example.com/sunset.jpg"`). Absolute URLs select
    `delivery=fetch` automatically unless overridden.

  * `options` is a keyword list. URL-shape options (`:host`,
    `:scheme`, `:mount`, `:account`, `:resource_type`, `:delivery`,
    `:signing_keys`, `:signing_expires_at`) are popped first; the
    remainder are translated into Cloudinary transform parameters.

  ### Examples

      iex> Image.Component.CDN.Cloudinary.URL.build("/sample.jpg", account: "demo", width: 800, fit: :cover, format: :webp)
      "/demo/image/upload/c_fill,f_webp,w_800/sample.jpg"

      iex> Image.Component.CDN.Cloudinary.URL.build("/sample.jpg", host: "res.cloudinary.com", account: "demo", width: 200)
      "https://res.cloudinary.com/demo/image/upload/w_200/sample.jpg"

  """
  @spec build(String.t(), keyword()) :: String.t()
  def build(source, options \\ []) when is_binary(source) and is_list(options) do
    {host, options} = Keyword.pop(options, :host)
    {scheme, options} = Keyword.pop(options, :scheme, "https")
    {mount, options} = Keyword.pop(options, :mount, "")
    {account, options} = Keyword.pop(options, :account)
    {resource_type, options} = Keyword.pop(options, :resource_type, "image")
    {delivery, options} = Keyword.pop(options, :delivery, default_delivery(source))
    {signing_keys, options} = Keyword.pop(options, :signing_keys)
    {signing_expires_at, options} = Keyword.pop(options, :signing_expires_at)

    transforms =
      options
      |> Enum.map(&encode_option/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()
      |> Enum.join(",")

    source_segment = normalise_source(source, delivery)
    origin = origin(host, scheme)
    mount_prefix = normalise_mount(mount)
    account_segment = if is_nil(account), do: "", else: "/" <> account

    base_path =
      case transforms do
        "" -> "#{account_segment}/#{resource_type}/#{delivery}/#{source_segment}"
        _ -> "#{account_segment}/#{resource_type}/#{delivery}/#{transforms}/#{source_segment}"
      end

    base = "#{origin}#{mount_prefix}#{base_path}"
    maybe_sign(base, signing_keys, signing_expires_at)
  end

  defp default_delivery("http://" <> _), do: "fetch"
  defp default_delivery("https://" <> _), do: "fetch"
  defp default_delivery(_), do: "upload"

  defp origin(nil, _scheme), do: ""
  defp origin("http://" <> _ = host, _scheme), do: host
  defp origin("https://" <> _ = host, _scheme), do: host
  defp origin(host, scheme) when is_binary(host), do: "#{scheme}://#{host}"

  defp normalise_mount(""), do: ""
  defp normalise_mount(mount), do: "/" <> String.trim(mount, "/")

  # `delivery=fetch` keeps the URL natural (Cloudinary accepts
  # `https://...` directly in the path). Otherwise strip a leading `/`
  # — Cloudinary public-ids don't have one.
  defp normalise_source("http://" <> _ = url, "fetch"), do: url
  defp normalise_source("https://" <> _ = url, "fetch"), do: url
  defp normalise_source("http://" <> _ = url, _), do: url
  defp normalise_source("https://" <> _ = url, _), do: url
  defp normalise_source("/" <> rest, _), do: rest
  defp normalise_source(other, _), do: other

  defp maybe_sign(url, nil, _expires_at), do: url

  defp maybe_sign(url, [_ | _] = keys, expires_at) do
    {origin, path} = split_origin(url)

    signed_path =
      case expires_at do
        nil -> Image.Component.CDN.Cloudinary.Signing.sign(path, keys)
        e -> Image.Component.CDN.Cloudinary.Signing.sign(path, keys, expires_at: e)
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

  defp encode_option({:width, n}) when is_integer(n) and n > 0, do: "w_#{n}"
  defp encode_option({:height, n}) when is_integer(n) and n > 0, do: "h_#{n}"
  defp encode_option({:dpr, n}) when is_integer(n) and n > 0, do: "dpr_#{n}"
  defp encode_option({:quality, n}) when is_integer(n) and n in 1..100, do: "q_#{n}"
  defp encode_option({:quality, :auto}), do: "q_auto"

  defp encode_option({:format, value}) when value in ~w(jpeg webp avif png auto)a do
    "f_#{format_to_string(value)}"
  end

  defp encode_option({:fit, value}) when value in ~w(contain cover crop pad scale_down squeeze)a do
    "c_#{fit_to_string(value)}"
  end

  defp encode_option({:gravity, atom}) when is_atom(atom), do: "g_#{gravity_to_string(atom)}"

  defp encode_option({:gravity, {:xy, x, y}}) when is_number(x) and is_number(y) do
    "g_xy_center,x_#{x},y_#{y}"
  end

  defp encode_option({:background, color}) when is_binary(color) do
    "b_rgb:#{String.trim_leading(color, "#")}"
  end

  defp encode_option({:blur, n}) when is_number(n) and n > 0 do
    # Inverse of the server's `sigma = N / 100`. Cap at Cloudinary's
    # documented 0..2000 range.
    "e_blur:#{trunc(min(n * 100, 2000))}"
  end

  defp encode_option({:sharpen, n}) when is_number(n) and n > 0 do
    "e_sharpen:#{trunc(min(n * 10, 100))}"
  end

  defp encode_option({:brightness, mult}) when is_number(mult), do: "e_brightness:#{adj(mult)}"
  defp encode_option({:contrast, mult}) when is_number(mult), do: "e_contrast:#{adj(mult)}"
  defp encode_option({:saturation, mult}) when is_number(mult), do: "e_saturation:#{adj(mult)}"
  defp encode_option({:gamma, mult}) when is_number(mult), do: "e_gamma:#{adj(mult)}"

  defp encode_option({:rotate, value}) when value in [90, 180, 270], do: "a_#{value}"

  # Unknown option → silently dropped.
  defp encode_option(_other), do: nil

  defp format_to_string(:jpeg), do: "jpg"
  defp format_to_string(other), do: Atom.to_string(other)

  defp fit_to_string(:contain), do: "fit"
  defp fit_to_string(:cover), do: "fill"
  defp fit_to_string(:crop), do: "crop"
  defp fit_to_string(:pad), do: "pad"
  defp fit_to_string(:scale_down), do: "limit"
  defp fit_to_string(:squeeze), do: "scale"

  defp gravity_to_string(:north), do: "north"
  defp gravity_to_string(:south), do: "south"
  defp gravity_to_string(:east), do: "east"
  defp gravity_to_string(:west), do: "west"
  defp gravity_to_string(:north_east), do: "north_east"
  defp gravity_to_string(:north_west), do: "north_west"
  defp gravity_to_string(:south_east), do: "south_east"
  defp gravity_to_string(:south_west), do: "south_west"
  defp gravity_to_string(:face), do: "face"
  defp gravity_to_string(:auto), do: "auto"
  defp gravity_to_string(:center), do: "center"
  defp gravity_to_string(other), do: Atom.to_string(other)

  defp adj(mult) do
    n = round((mult - 1.0) * 100)
    n |> max(-100) |> min(100)
  end
end
