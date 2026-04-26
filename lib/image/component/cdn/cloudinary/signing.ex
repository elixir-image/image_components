defmodule Image.Component.CDN.Cloudinary.Signing do
  @moduledoc """
  Cloudinary-flavoured client-side URL signing.

  Wire-format-compatible with `Image.Plug.Provider.Cloudinary.Signing`
  on the server side and with Cloudinary's hosted signed URLs.
  Sign-only — verification happens at the back-end.

  SHA-256 over `<transforms>/<source><api-secret>`. Signature is
  inserted as a path segment `s--<base64url-truncated-32>--`
  between the delivery type (`upload`) and the first transform
  stage.
  """

  @digest_length 32

  @doc """
  Signs a Cloudinary path with the first key in `keys`.

  ### Arguments

  * `path` is the path of a Cloudinary URL **without** an
    `s--<sig>--` segment.

  * `keys` is a non-empty list of API secrets.

  ### Options

  * `:expires_at` — currently unused. Cloudinary's signed-URL flow
    relies on path-bound signatures rather than a per-URL expiry
    parameter; key rotation handles long-term revocation.
  """
  @spec sign(String.t(), [String.t(), ...], keyword()) :: String.t()
  def sign(path, [primary_key | _] = _keys, _options \\ [])
      when is_binary(path) and is_binary(primary_key) do
    {prefix, transforms_and_source} = split_at_delivery(path)
    signature = compute_signature(transforms_and_source, primary_key)
    "#{prefix}/s--#{signature}--/#{transforms_and_source}"
  end

  defp split_at_delivery(path) do
    segments = String.split(String.trim_leading(path, "/"), "/")

    case segments do
      [account, resource_type, delivery | rest] ->
        prefix = "/" <> account <> "/" <> resource_type <> "/" <> delivery
        {prefix, Enum.join(rest, "/")}

      _ ->
        {"", String.trim_leading(path, "/")}
    end
  end

  defp compute_signature(transforms_and_source, key) do
    :crypto.hash(:sha256, transforms_and_source <> key)
    |> Base.url_encode64(padding: false)
    |> String.slice(0, @digest_length)
  end
end
