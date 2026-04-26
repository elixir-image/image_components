defmodule Image.Component.LayoutTest do
  use ExUnit.Case, async: true
  doctest Image.Component.Layout

  alias Image.Component.Layout

  describe "compute/4 :fixed" do
    test "produces a density-descriptor ladder at 1x/2x/3x of the intrinsic width" do
      layout = Layout.compute(:fixed, 200, 100)

      assert layout.mode == :fixed
      assert layout.srcset_kind == :density
      assert layout.widths == [200, 400, 600]
    end

    test "honours custom :dpr_factors" do
      layout = Layout.compute(:fixed, 100, 100, dpr_factors: [1, 2])
      assert layout.widths == [100, 200]
    end

    test "style sets explicit pixel width and height" do
      layout = Layout.compute(:fixed, 200, 100)
      assert layout.style =~ "width: 200px"
      assert layout.style =~ "height: 100px"
    end
  end

  describe "compute/4 :constrained" do
    test "produces a width-descriptor ladder capped at the intrinsic width" do
      layout = Layout.compute(:constrained, 800, 600)

      assert layout.mode == :constrained
      assert layout.srcset_kind == :width
      assert Enum.max(layout.widths) == 800
      assert 800 in layout.widths
    end

    test "ladder respects max_width override" do
      layout = Layout.compute(:constrained, 1600, 1200, max_width: 1024)
      assert Enum.max(layout.widths) == 1024
    end

    test "style includes aspect-ratio for CLS prevention when height is set" do
      layout = Layout.compute(:constrained, 800, 600)
      assert layout.style =~ "aspect-ratio: 800 / 600"
      assert layout.style =~ "max-width: 800px"
    end

    test "style without height omits aspect-ratio" do
      layout = Layout.compute(:constrained, 800, nil)
      refute layout.style =~ "aspect-ratio"
      assert layout.style =~ "max-width: 800px"
    end
  end

  describe "compute/4 :full_width" do
    test "produces a width-descriptor ladder regardless of intrinsic dims" do
      layout = Layout.compute(:full_width, nil, nil)

      assert layout.mode == :full_width
      assert layout.srcset_kind == :width
      assert is_list(layout.widths)
      assert length(layout.widths) > 0
    end

    test "max_width caps the ladder" do
      layout = Layout.compute(:full_width, nil, nil, max_width: 1200)
      assert Enum.all?(layout.widths, &(&1 <= 1200))
    end

    test "style fills the viewport" do
      layout = Layout.compute(:full_width, nil, nil)
      assert layout.style == "width: 100%; height: auto;"
    end
  end

  describe "fallback / invalid input" do
    test "constrained without a width falls through to a defensive constrained layout" do
      layout = Layout.compute(:constrained, nil, nil)
      assert layout.mode == :constrained
      assert layout.srcset_kind == :width
    end
  end
end
