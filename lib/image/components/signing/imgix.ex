defmodule Image.Components.Signing.Imgix do
  @moduledoc """
  imgix-flavoured client-side URL signing.

  Wire-format-compatible with `Image.Plug.Provider.Imgix.Signing`
  on the server side and with imgix's hosted signed URLs.
  Sign-only — verification happens at the back-end.

  HMAC-SHA256 over `secret <> path-and-query`. Signature appended
  as `?s=<hex>` (or `&s=<hex>` if a query is already present).
  """

  @signature_param "s"
  @expiry_param "expires"

  @doc """
  Signs `path_with_query` with the first key in `keys`.

  ### Arguments

  * `path_with_query` is the imgix request path, optionally with
    an existing query string.

  * `keys` is a non-empty list of imgix secret tokens.

  ### Options

  * `:expires_at` — `DateTime` or unix-seconds. Adds an
    `expires=<unix>` parameter; the back-end's verifier rejects
    the URL after that time.

  ### Returns

  * The path with `?s=<hex>` (and optional `?expires=…`) appended.

  ### Examples

      iex> Image.Components.Signing.Imgix.sign("/cat.jpg?w=200", ["secret"])
      ...> =~ "?w=200&s="
      true

  """
  @spec sign(String.t(), [String.t(), ...], keyword()) :: String.t()
  def sign(path_with_query, [primary_key | _] = _keys, options \\ [])
      when is_binary(path_with_query) and is_binary(primary_key) do
    base =
      case encode_expiry(Keyword.get(options, :expires_at)) do
        nil -> path_with_query
        param -> append_query(path_with_query, param)
      end

    signature = hmac(primary_key, base)
    append_query(base, "#{@signature_param}=#{signature}")
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
    :crypto.mac(:hmac, :sha256, key, key <> payload) |> Base.encode16(case: :lower)
  end
end
