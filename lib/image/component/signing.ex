defmodule Image.Component.Signing do
  @moduledoc """
  Client-side HMAC signing for URLs emitted by `Image.Component.URL`.

  Functionally equivalent to `Image.Plug.Signing` on the back-end:
  HMAC-SHA256 over the path-and-query (with the `sig` parameter
  removed), hex-encoded, appended as `?sig=<hex>`. Sign-only — the
  back-end verifies. Use this when your `Image.Plug` deployment is
  configured with `:signing` and you need the component to emit
  authentic URLs.

  Self-contained — does not depend on `image_plug`. Both packages
  share the wire format, not the code.

  ### Example

      iex> path = "/cdn-cgi/image/width=200/photo.jpg"
      iex> signed = Image.Component.Signing.sign(path, ["secret"])
      iex> String.starts_with?(signed, path <> "?sig=")
      true

  """

  @signature_param "sig"
  @expiry_param "exp"

  @doc """
  Signs `path` with the first key in `keys`.

  ### Arguments

  * `path` is the request path (with or without an existing query
    string).

  * `keys` is a non-empty list of secret-key strings. The first
    key is used.

  ### Options

  * `:expires_at` — `DateTime` or unix-seconds integer. When set,
    appends `?exp=<unix-seconds>` and signs the result.

  ### Returns

  * The path with `?sig=<hex>` (and optional `?exp=...`) appended.

  ### Examples

      iex> Image.Component.Signing.sign("/foo.jpg", ["secret"])
      ...> |> String.starts_with?("/foo.jpg?sig=")
      true

      iex> Image.Component.Signing.sign("/foo.jpg?other=1", ["secret"])
      ...> =~ "?other=1&sig="
      true

  """
  @spec sign(String.t(), [String.t(), ...], keyword()) :: String.t()
  def sign(path, [primary_key | _], options \\ [])
      when is_binary(path) and is_binary(primary_key) do
    expiry_param = encode_expiry(Keyword.get(options, :expires_at))

    base_with_expiry =
      case expiry_param do
        nil -> path
        param -> append_query(path, param)
      end

    signature = hmac(primary_key, base_with_expiry)
    append_query(base_with_expiry, "#{@signature_param}=#{signature}")
  end

  defp encode_expiry(nil), do: nil
  defp encode_expiry(value) when is_integer(value), do: "#{@expiry_param}=#{value}"

  defp encode_expiry(%DateTime{} = dt) do
    "#{@expiry_param}=#{DateTime.to_unix(dt)}"
  end

  defp append_query(path, param) do
    case String.contains?(path, "?") do
      true -> "#{path}&#{param}"
      false -> "#{path}?#{param}"
    end
  end

  defp hmac(key, payload) when is_binary(key) and is_binary(payload) do
    :crypto.mac(:hmac, :sha256, key, payload) |> Base.encode16(case: :lower)
  end
end
