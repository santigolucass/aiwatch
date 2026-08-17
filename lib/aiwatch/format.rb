# frozen_string_literal: true

require_relative "tui/ansi"

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

    # Elapsed time since `time`, as a short duration ("16h", "38m", "13s")
    # rather than relative_time's "16h ago" — for a STARTED column where
    # "ago" would repeat across every row.
    def uptime(time, now: Time.now)
      return "-" if time.nil?

      delta = (now - time).to_i
      return "-" if delta.negative?

      if delta < 60
        "#{delta}s"
      elsif delta < 3600
        "#{delta / 60}m"
      elsif delta < 86_400
        "#{delta / 3600}h"
      else
        "#{delta / 86_400}d"
      end
    end

    def duration_ms(ms)
      return "-" if ms.nil?

      seconds = ms / 1000.0
      (seconds < 60) ? format("%.1fs", seconds) : "#{(seconds / 60).round}m"
    end

    def percent(fraction)
      return "?" if fraction.nil?

      "#{(fraction * 100).round}%"
    end

    def count(n)
      return "0" if n.nil?

      n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
    end

    def clock(time)
      return "--:--:--" if time.nil?

      time.strftime("%H:%M:%S")
    end

    # Truncates a filesystem path from the left (keeping the tail, which
    # is usually the more identifying part) to fit a column width.
    def short_path(path, max)
      return "?" if path.nil?

      Tui::Ansi.truncate(path, max, from: :left)
    end
  end
end
