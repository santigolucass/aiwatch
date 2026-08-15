# frozen_string_literal: true

module Aiwatch
  # Human-facing number and time formatting shared by every renderer.
  module Format
    module_function

    def tokens(count)
      return "0" if count.zero?

      abs = count.abs
      if abs >= 1_000_000
        "#{trim_decimal(count / 1_000_000.0)}M"
      elsif abs >= 1_000
        "#{trim_decimal(count / 1_000.0)}K"
      else
        count.to_s
      end
    end

    def trim_decimal(value)
      format("%.1f", value).sub(/\.0\z/, "")
    end

    def cost(amount, unknown: false)
      return "?" if unknown || amount.nil?

      format("$%.4f", amount)
    end

    def relative_time(time, now: Time.now)
      return "-" if time.nil?

      delta = (now - time).to_i
      if delta < 60
        "just now"
      elsif delta < 3600
        "#{delta / 60}m ago"
      elsif delta < 86_400
        "#{delta / 3600}h ago"
      elsif delta < 7 * 86_400
        "#{delta / 86_400}d ago"
      else
        time.strftime("%Y-%m-%d")
      end
    end
  end
end
