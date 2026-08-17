# frozen_string_literal: true

module Aiwatch
  module Live
    # Table-driven key -> action mapping. The footer's KEYS line and the
    # `?` help overlay are both generated from FOOTER_GROUPS rather than
    # hand-written strings, so the two can never drift out of sync with
    # what a key actually does.
    module Keymap
      BROWSE_ACTIONS = {
        "j" => :down, "k" => :up, "h" => :left, "l" => :right,
        :down => :down, :up => :up, :left => :left, :right => :right,
        :home => :first, :end => :last, :pgup => :log_scroll_up, :pgdn => :log_scroll_down, :esc => :view_dash,
        "x" => :kill, "X" => :force_kill, "A" => :purge, "K" => :kill_all,
        "p" => :toggle_pin, "s" => :cycle_sort, "/" => :filter, "F" => :search,
        "r" => :refresh, "o" => :open, "G" => :cycle_group, "L" => :toggle_log,
        "W" => :view_timeline, "E" => :export, "T" => :cycle_theme, "d" => :view_dash,
        "H" => :view_history, "C" => :view_heatmap, "?" => :help,
        "q" => :quit, ?\C-c => :quit
      }.freeze

      CONFIRM_ACTIONS = {
        "y" => :confirm, "Y" => :confirm, "n" => :cancel, "N" => :cancel, :esc => :cancel,
        "q" => :quit, ?\C-c => :quit
      }.freeze

      # In :input mode (filter/search/export path/kill-all confirmation)
      # only these control keys resolve to an action; every other key —
      # printable characters — is text for the input buffer, handled
      # directly by App rather than through this table.
      INPUT_ACTIONS = {
        :enter => :commit_input, :esc => :cancel_input, :backspace => :backspace,
        ?\C-c => :quit
      }.freeze

      OVERLAY_ACTIONS = {
        :esc => :cancel, "q" => :quit, ?\C-c => :quit, "?" => :cancel
      }.freeze

      # [key label, action label] pairs, in the order they render in the
      # footer and the help overlay.
      FOOTER_GROUPS = [
        %w[hjkl Nav], %w[x Kill], %w[X Force], %w[A Purge], %w[K All],
        %w[p Pin], %w[s Sort], ["/", "Filter"], %w[F Search], %w[r Refresh],
        %w[o Open], %w[G Group], %w[L Log], %w[W Timeline], %w[E Export],
        %w[T Theme], %w[d Dash], %w[H History], %w[C Heatmap], %w[? Help]
      ].freeze

      module_function

      def action_for(key, mode:)
        case mode
        when :confirm then CONFIRM_ACTIONS[key]
        when :input then INPUT_ACTIONS[key]
        when :dash, :browse then BROWSE_ACTIONS[key]
        else OVERLAY_ACTIONS[key] || BROWSE_ACTIONS[key]
        end
      end

      def footer_text
        "KEYS: #{FOOTER_GROUPS.map { |k, l| "#{k} #{l}" }.join("  ")}"
      end
    end
  end
end
