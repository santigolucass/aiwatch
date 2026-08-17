# frozen_string_literal: true

module Aiwatch
  module Tui
    # Resolves a semantic role (:active, :cost, :border, one of the
    # per-session palette slots...) to an SGR escape, at whatever color
    # depth the terminal actually supports — 256-color, the 16-color
    # fallback, or none at all (NO_COLOR, TERM=dumb, or a non-tty).
    #
    # Also resolves named glyphs to characters. Every glyph a renderer
    # wants to put in a column TextTable/Grid measures must go through
    # here rather than being written inline, so `--ascii` (or a non-UTF-8
    # locale) can swap the whole set at once — see docs/decisions.md for
    # the two times this project got bitten by a glyph's terminal width
    # not matching its character count.
    class Theme
      DEPTHS = %i[none ansi16 ansi256].freeze

      # role => [ansi256 fg, ansi16 fg]. Presets only vary the background
      # and border framing; role colors are shared so status meaning
      # (active/dead/warning) stays consistent across themes.
      ROLE_COLORS = {
        active: [82, 32],     # green
        dead: [244, 90],      # grey
        warning: [214, 33],   # amber
        error: [203, 31],     # red
        cost: [222, 33],      # yellow
        accent: [39, 36],     # cyan
        muted: [245, 90],     # grey
        header: [208, 33],    # orange
        border: [208, 33],    # orange
        title: [255, 97],     # bright white
        selected_fg: [16, 30],
        selected_bg: [214, 43]
      }.freeze

      # Stable per-session color cycle, 256-color first, 16-color fallback.
      SESSION_PALETTE = [
        [82, 32], [45, 36], [220, 33], [213, 35], [75, 34], [203, 31], [120, 92], [214, 90]
      ].freeze

      PRESETS = {
        purple: {bg: 54, panel_bg: 55, border: 208},
        matrix: {bg: 16, panel_bg: 16, border: 82},
        mono: {bg: nil, panel_bg: nil, border: 250}
      }.freeze

      GLYPHS = {
        unicode: {
          active_dot: "●", dead_dot: "○", cursor: "❯", pin: "📌", up: "▲", down: "▼",
          box_tl: "┌", box_tr: "┐", box_bl: "└", box_br: "┘", box_h: "─", box_v: "│",
          box_t_left: "├", box_t_right: "┤", ellipsis: "…", bar_full: "█", bar_empty: "░"
        },
        ascii: {
          active_dot: "*", dead_dot: "o", cursor: ">", pin: "P", up: "^", down: "v",
          box_tl: "+", box_tr: "+", box_bl: "+", box_br: "+", box_h: "-", box_v: "|",
          box_t_left: "+", box_t_right: "+", ellipsis: "...", bar_full: "#", bar_empty: "-"
        }
      }.freeze

      attr_reader :depth, :preset, :ascii

      def self.detect(out: $stdout, env: ENV)
        return :none if env["NO_COLOR"] && !env["NO_COLOR"].empty?
        return :none unless out.respond_to?(:tty?) && out.tty?
        return :none if env["TERM"] == "dumb"

        term = env["COLORTERM"].to_s
        colorterm256 = env["TERM"].to_s.include?("256color")
        (term.include?("truecolor") || term.include?("24bit") || colorterm256) ? :ansi256 : :ansi16
      end

      def initialize(depth: :ansi256, preset: :purple, ascii: false)
        @depth = DEPTHS.include?(depth) ? depth : :ansi256
        @preset = PRESETS.key?(preset) ? preset : :purple
        @ascii = ascii
        @glyphs = ascii ? GLYPHS[:ascii] : GLYPHS[:unicode]
      end

      def color?
        @depth != :none
      end

      def next_preset
        keys = PRESETS.keys
        keys[(keys.index(@preset) + 1) % keys.length]
      end

      # Themes are otherwise immutable (every color/depth decision is
      # frozen at construction) — this is the one exception, since `T`
      # cycling presets mid-run is a real interaction, not a setup-time
      # choice. Returns a new instance rather than mutating in place, so
      # nothing else can be holding a stale reference to the old preset.
      def with_preset(preset)
        self.class.new(depth: @depth, preset: preset, ascii: @ascii)
      end

      def glyph(name)
        @glyphs.fetch(name, "?")
      end

      def sgr(role, bold: false)
        return "" unless color?

        code = role_code(role)
        return "" unless code

        fg_sgr(code, bold: bold)
      end

      def paint(text, role, bold: false)
        prefix = sgr(role, bold: bold)
        return text.to_s if prefix.empty?

        "#{prefix}#{text}\e[0m"
      end

      def session_color(index)
        pair = SESSION_PALETTE[index % SESSION_PALETTE.length]
        (@depth == :ansi256) ? pair.first : pair.last
      end

      def paint_session(text, index, bold: false)
        return text.to_s unless color?

        "#{fg_sgr(session_color(index), bold: bold)}#{text}\e[0m"
      end

      def background_sgr(kind = :bg)
        return "" unless color? && @depth == :ansi256

        code = PRESETS.fetch(@preset).fetch(kind, nil)
        code ? "\e[48;5;#{code}m" : ""
      end

      private

      # `code` is a bare 16-color SGR parameter (30-37) at :ansi16 depth,
      # or a 256-color palette index at :ansi256 depth — those need the
      # extended `38;5;<index>` form, not the bare index as a raw SGR
      # parameter (which isn't a valid code at all and was silently
      # producing garbage escapes in a real terminal before this fix).
      def fg_sgr(code, bold:)
        prefix = bold ? "1;" : ""
        (@depth == :ansi256) ? "\e[#{prefix}38;5;#{code}m" : "\e[#{prefix}#{code}m"
      end

      def role_code(role)
        pair = ROLE_COLORS[role]
        return nil unless pair

        (@depth == :ansi256) ? pair.first : pair.last
      end
    end
  end
end
