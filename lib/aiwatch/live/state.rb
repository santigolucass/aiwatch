# frozen_string_literal: true

module Aiwatch
  module Live
    # Pure UI state: no IO, no sensors, no rendering. Everything the
    # dashboard remembers between frames that isn't itself session data —
    # selection, mode, which view is showing, pins, purges, sort/filter/
    # search, and the text-entry buffer shared by filter/search/export's
    # input mode. Kept separate from App specifically so it stays the
    # densest, fastest unit test target in the whole rewrite: no fakes,
    # no IO, just data in and data out.
    class State
      VIEWS = %i[dash timeline history heatmap help].freeze
      SORT_KEYS = %i[last_activity cost started name].freeze

      attr_accessor :view, :mode, :selected_id, :pending_kill_id, :pending_kill_signal,
        :status_message, :log_scroll, :sort_key, :filter_text, :search_text,
        :group_by, :show_dead, :log_expanded, :input_buffer, :input_purpose, :theme_preset

      def initialize
        @view = :dash
        @mode = :browse
        @selected_id = nil
        @pending_kill_id = nil
        @pending_kill_signal = "TERM"
        @status_message = nil
        @log_scroll = 0
        @sort_key = :last_activity
        @filter_text = ""
        @search_text = ""
        @group_by = :kind
        @theme_preset = :purple
        @show_dead = true
        @log_expanded = false
        @pinned_ids = {}
        @purged_ids = {}
        @input_buffer = +""
        @input_purpose = nil
      end

      def pinned?(id)
        @pinned_ids.key?(id)
      end

      def toggle_pin(id)
        @pinned_ids.key?(id) ? @pinned_ids.delete(id) : @pinned_ids[id] = true
      end

      def purge(id)
        @purged_ids[id] = true
      end

      def purge_all_dead(sessions)
        sessions.each { |s| @purged_ids[s.id] = true if s.dead? }
      end

      def cycle_sort
        @sort_key = SORT_KEYS[(SORT_KEYS.index(@sort_key) + 1) % SORT_KEYS.length]
      end

      def cycle_group
        @group_by = (@group_by == :kind) ? :none : :kind
      end

      # Filters, sorts, and pins-first orders a list of LiveSession.
      # cost_for: optional Proc(session) -> Float, only consulted when
      # sort_key is :cost — keeps State itself free of a CostCalculator
      # dependency; App supplies the lookup.
      def visible(sessions, cost_for: nil)
        list = sessions.reject { |s| @purged_ids.key?(s.id) }
        list = @show_dead ? list : list.reject(&:dead?)
        list = apply_filter(list)
        list = apply_sort(list, cost_for)
        pinned, rest = list.partition { |s| pinned?(s.id) }
        pinned + rest
      end

      # Re-syncs selection after a refresh: if the selected session
      # disappeared (went inactive, got killed, filtered out), fall back
      # to the first remaining session rather than pointing at whatever
      # now occupies that row index, which would silently select the
      # wrong session.
      def sync_selection(visible_sessions)
        if visible_sessions.empty?
          @selected_id = nil
        elsif visible_sessions.none? { |s| s.id == @selected_id }
          @selected_id = visible_sessions.first.id
        end
      end

      def move_selection(visible_sessions, delta)
        return if visible_sessions.empty?

        index = visible_sessions.index { |s| s.id == @selected_id } || 0
        @selected_id = visible_sessions[(index + delta).clamp(0, visible_sessions.length - 1)].id
      end

      # Selects the next session (after the currently selected one, or
      # from the top) whose title/project/branch matches `search_text`.
      # Wraps around. No-op (returns false) when nothing matches.
      def jump_to_next_match(visible_sessions)
        return false if @search_text.to_s.empty? || visible_sessions.empty?

        matches = visible_sessions.select { |s| matches_text?(s, @search_text) }
        return false if matches.empty?

        current_index = visible_sessions.index { |s| s.id == @selected_id } || -1
        next_match = matches.find { |s| visible_sessions.index { |v| v.id == s.id } > current_index }
        @selected_id = (next_match || matches.first).id
        true
      end

      private

      def matches_text?(session, needle)
        haystack = [session.title, session.project, session.branch]
        haystack.compact.any? { |f| f.downcase.include?(needle.downcase) }
      end

      def apply_filter(list)
        return list if @filter_text.to_s.empty?

        list.select { |s| matches_text?(s, @filter_text) }
      end

      def apply_sort(list, cost_for)
        case @sort_key
        when :cost
          list.sort_by { |s| -(cost_for ? cost_for.call(s) : 0.0) }
        when :started
          list.sort_by { |s| s.first_seen_at || Time.at(0) }
        when :name
          list.sort_by { |s| (s.title || "").downcase }
        else
          list.sort_by { |s| s.last_seen_at || Time.at(0) }.reverse
        end
      end
    end
  end
end
