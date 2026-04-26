defmodule Image.Component.CDN do
  @moduledoc """
  Behaviour for CDN URL adapters used by `Image.Component`.

  A CDN adapter encapsulates the URL grammar and signing scheme for
  one image-CDN family. The component dispatches every URL it
  builds through the configured adapter, so swapping CDNs is a one-
  line config change rather than a rewrite.

  ### Built-in adapters

  * `Image.Component.CDN.Cloudflare` — the [Cloudflare Images URL
    grammar](https://developers.cloudflare.com/images/transform-images/transform-via-url/),
    matching what `image_plug` and Cloudflare's hosted Images
    service both speak. The default.

  ### Selecting an adapter

  Configure via `Application.get_env(:image_components, :defaults)`:

      config :image_components,
        defaults: [
          cdn: :cloudflare        # atom shorthand for the built-in
        ]

  Or pass per-call via `:cdn`:

      <.image cdn={:cloudflare} ... />

  Or use the full `{module, opts}` form to swap in a custom adapter:

      <.image cdn={MyApp.MyCDN} ... />

  ### Adding a new adapter

  Implement `c:build_url/2` and `c:sign_url/3` in a module of your
  choice, then reference the module via the `:cdn` option.

  See `Image.Component.CDN.Cloudflare` for a reference implementation.
  """

  @doc """
  Builds a request URL from a source path/URL and a keyword list of
  options.

  Options accepted are CDN-specific. The Cloudflare adapter accepts
  every key documented in `Image.Component.URL` (Cloudflare options
  like `:width`, `:height`, `:fit`, `:quality`, `:format`, etc.,
  plus URL-shape options like `:host`, `:scheme`, `:mount`).
  """
  @callback build_url(source :: String.t(), options :: keyword()) :: String.t()

  @doc """
  Signs `url` with the first key in `keys`.

  ### Options

  * `:expires_at` — `DateTime` or unix-seconds. Adapter-specific
    behaviour; the Cloudflare adapter appends `?exp=<unix-seconds>`
    to the signed URL.

  Returns the signed URL.
  """
  @callback sign_url(url :: String.t(), keys :: [String.t(), ...], options :: keyword()) ::
              String.t()

  @doc """
  Resolves a `:cdn` configuration value (atom shorthand, module, or
  `{module, opts}` tuple) to a `{module, opts}` pair.

  ### Returns

  * `{module, opts}` ready for callback dispatch.

  ### Examples

      iex> Image.Component.CDN.resolve(:cloudflare)
      {Image.Component.CDN.Cloudflare, []}

      iex> Image.Component.CDN.resolve(nil)
      {Image.Component.CDN.Cloudflare, []}

      iex> Image.Component.CDN.resolve({Image.Component.CDN.Cloudflare, [foo: 1]})
      {Image.Component.CDN.Cloudflare, [foo: 1]}

  """
  @spec resolve(atom() | module() | {module(), keyword()} | nil) :: {module(), keyword()}
  def resolve(nil), do: {Image.Component.CDN.Cloudflare, []}
  def resolve(:cloudflare), do: {Image.Component.CDN.Cloudflare, []}
  def resolve(:imgix), do: {Image.Component.CDN.Imgix, []}
  def resolve(:cloudinary), do: {Image.Component.CDN.Cloudinary, []}
  def resolve(:image_kit), do: {Image.Component.CDN.ImageKit, []}
  def resolve({module, opts}) when is_atom(module) and is_list(opts), do: {module, opts}

  def resolve(module) when is_atom(module) do
    if function_exported?(module, :__info__, 1) do
      {module, []}
    else
      raise ArgumentError,
            "Image.Component: unknown CDN adapter #{inspect(module)}. " <>
              "Pass `:cloudflare` for the built-in, or a module that implements " <>
              "the Image.Component.CDN behaviour."
    end
  end
end
