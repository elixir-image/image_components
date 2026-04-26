defmodule Image.Component.CDN.ImageKit.Signing do
  @moduledoc """
  ImageKit-flavoured client-side URL signing.

  Wire-format-compatible with `Image.Plug.Provider.ImageKit.Signing`
  on the server side and with ImageKit's hosted signed URLs.
  Sign-only — verification happens at the back-end.

  HMAC-SHA1 over the path-and-query (`ik-s` excluded). Signature
  appended as `?ik-s=<hex>` (or `&ik-s=<hex>` if a query is already
  present).
  """

  @signature_param "ik-s"
  @expiry_param "ik-t"

  @doc """
  Signs `path_with_query` with the first key in `keys`.

  ### Options

  * `:expires_at` — `DateTime` or unix-seconds. Adds an
    `ik-t=<unix>` parameter; the back-end's verifier rejects after
    that time.
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
    :crypto.mac(:hmac, :sha, key, payload) |> Base.encode16(case: :lower)
  end
end
