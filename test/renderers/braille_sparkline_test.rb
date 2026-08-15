# frozen_string_literal: true

require_relative "../test_helper"

class RenderersBrailleSparklineTest < Minitest::Test
  BLANK = 0x2800

  def test_all_zero_series_renders_as_blank
    out = Aiwatch::Renderers::BrailleSparkline.render([0] * 10, width: 5)

    assert_equal 5, out.length
    assert(out.codepoints.all? { |cp| cp == BLANK })
  end

  def test_pads_shorter_series_on_the_left_with_zeros
    # A single trailing sample lands in the last character's *right*
    # sub-column (newest), with the left sub-column left blank (padding).
    out = Aiwatch::Renderers::BrailleSparkline.render([100], width: 1)

    assert_equal BLANK + 0xB8, out.ord
  end

  def test_self_normalizes_to_its_own_max
    out = Aiwatch::Renderers::BrailleSparkline.render([50, 100], width: 1)

    assert_equal BLANK + 0xFC, out.ord
  end

  def test_width_determines_character_count_regardless_of_series_length
    out = Aiwatch::Renderers::BrailleSparkline.render((1..20).to_a, width: 7)

    assert_equal 7, out.length
  end

  def test_negative_and_nil_values_are_treated_as_zero
    out = Aiwatch::Renderers::BrailleSparkline.render([-5, nil, 10], width: 1)

    # last_n_padded takes the last 2 of 3 values: [nil, 10]
    assert_equal BLANK + 0xB8, out.ord
  end

  def test_empty_series_renders_blank_at_the_requested_width
    out = Aiwatch::Renderers::BrailleSparkline.render([], width: 4)

    assert_equal 4, out.length
    assert(out.codepoints.all? { |cp| cp == BLANK })
  end
end
