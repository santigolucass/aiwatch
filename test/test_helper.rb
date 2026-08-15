# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "aiwatch"
require "minitest/autorun"

module FixturePath
  def fixture_path(*segments)
    File.join(__dir__, "fixtures", *segments)
  end
end
