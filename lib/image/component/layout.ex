defmodule Image.Component.Layout do
  @moduledoc """
  Layout-mode helpers for the responsive-image component.

  Mirrors [`@unpic/core`](https://github.com/ascorbic/unpic-img/blob/main/packages/core/src)
  ' three layout modes:

  * `:fixed` — the image renders at a single intrinsic size
    regardless of viewport. Use for logos, fixed-size avatars, and
    icons. Generates a DPR-descriptor `srcset` (`1x`, `2x`, `3x`)
    rather than width descriptors.

  * `:constrained` — the image scales down with its container but
    never up beyond its intrinsic width. The default for hero and
    content images. Generates a width-descriptor `srcset` capped at
    the intrinsic width.

  * `:full_width` — the image always fills the viewport (or its
    container, when bounded by CSS). Generates a width-descriptor
    `srcset` covering the full default width ladder.

  Each mode produces a `t:layout/0` value plus a recommended `style`
  string that the component injects on the `<img>` to prevent CLS
  by reserving the right amount of layout space.
  """

  @typedoc """
  Layout mode atom. See moduledoc.
  """
  @type mode :: :fixed | :constrained | :full_width

  @typedoc """
  Computed layout for an image. Used by `Image.Component.Srcset` to
  pick widths and by `Image.Component` to set inline CSS.
  """
  @type t :: %{
          mode: mode(),
          widths: [pos_integer(), ...],
          srcset_kind: :width | :density,
          style: String.t()
        }

  @default_constrained_widths [320, 480, 640, 800, 1024, 1280, 1600, 1920, 2560]
  @default_full_width_widths [640, 750, 828, 1080, 1200, 1920, 2048, 3840]
  @default_dpr_factors [1, 2, 3]

  @doc """
  Returns a `t:t/0` describing the layout for a given mode +
  intrinsic dimensions.

  ### Arguments

  * `mode` is one of `t:mode/0`.

  * `width` is the intrinsic display width in CSS pixels (or `nil`
    when not statically known — only valid for `:full_width`).

  * `height` is the intrinsic display height in CSS pixels (or `nil`).

  ### Options

  * `:widths` — explicit width ladder. Overrides the per-mode default.

  * `:dpr_factors` — explicit DPR-factor ladder for `:fixed`. Defaults
    to `[1, 2, 3]`.

  * `:max_width` — cap applied to width-descriptor srcsets after the
    ladder is generated.

  ### Returns

  * A `t:t/0` map.

  ### Examples

      iex> layout = Image.Component.Layout.compute(:fixed, 200, 100)
      iex> {layout.mode, layout.srcset_kind, layout.widths}
      {:fixed, :density, [200, 400, 600]}

      iex> layout = Image.Component.Layout.compute(:constrained, 800, 600)
      iex> layout.srcset_kind
      :width
      iex> Enum.max(layout.widths)
      800

      iex> layout = Image.Component.Layout.compute(:full_width, nil, nil)
      iex> layout.mode
      :full_width

  """
  @spec compute(mode(), pos_integer() | nil, pos_integer() | nil, keyword()) :: t()
  def compute(mode, width, height, options \\ [])

  def compute(:fixed, width, height, options) when is_integer(width) and width > 0 do
    factors = Keyword.get(options, :dpr_factors) || @default_dpr_factors

    %{
      mode: :fixed,
      widths: Enum.map(factors, &(width * &1)),
      srcset_kind: :density,
      style: fixed_style(width, height)
    }
  end

  def compute(:constrained, width, height, options) when is_integer(width) and width > 0 do
    base = Keyword.get(options, :widths) || @default_constrained_widths
    max_width = Keyword.get(options, :max_width) || width

    widths =
      base
      |> Enum.filter(&(&1 <= max_width))
      |> Enum.uniq()
      |> Enum.sort()
      |> ensure_includes(min(width, max_width))

    %{
      mode: :constrained,
      widths: widths,
      srcset_kind: :width,
      style: constrained_style(width, height)
    }
  end

  def compute(:full_width, _width, _height, options) do
    base = Keyword.get(options, :widths) || @default_full_width_widths
    max_width = Keyword.get(options, :max_width)

    widths =
      base
      |> Enum.filter(fn w -> is_nil(max_width) or w <= max_width end)
      |> Enum.uniq()
      |> Enum.sort()

    %{
      mode: :full_width,
      widths: widths,
      srcset_kind: :width,
      style: "width: 100%; height: auto;"
    }
  end

  def compute(_mode, _width, _height, _options) do
    # Fallback: treat as constrained with no max-width cap. Lets the
    # component recover from missing :width gracefully.
    %{
      mode: :constrained,
      widths: @default_constrained_widths,
      srcset_kind: :width,
      style: ""
    }
  end

  defp fixed_style(width, height) when is_integer(height) and height > 0 do
    "width: #{width}px; height: #{height}px;"
  end

  defp fixed_style(width, _height) do
    "width: #{width}px; height: auto;"
  end

  # Constrained: the CSS keeps the image within its intrinsic width
  # but lets it scale down. Aspect-ratio reserves layout space to
  # prevent CLS even before the image loads.
  defp constrained_style(width, height) when is_integer(height) and height > 0 do
    "max-width: #{width}px; width: 100%; height: auto; aspect-ratio: #{width} / #{height};"
  end

  defp constrained_style(width, _height) do
    "max-width: #{width}px; width: 100%; height: auto;"
  end

  defp ensure_includes(widths, target) do
    if target in widths do
      widths
    else
      Enum.sort([target | widths])
    end
  end
end
