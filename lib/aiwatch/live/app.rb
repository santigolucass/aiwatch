# frozen_string_literal: true

module Aiwatch
  module Live
    # The dashboard's main loop: read a key, act on it, refresh data on a
    # timeout or on demand, sample process sensors, draw a frame. Every
    # external dependency (screen IO, key source, the session store,
    # /proc scanning, git branch reads, killing a process, the clock) is
    # an injected seam so this can be driven entirely by fakes in tests.
    class App
      REFRESH_SECONDS = 2

      def initialize(store:, cost_calculator:, pricing_table:,
        screen: Tui::Screen.new, theme: Tui::Theme.new,
        active_threshold_minutes: 5, refresh_seconds: REFRESH_SECONDS,
        clock: -> { Time.now }, read_key: nil, in_stream: $stdin,
        process_finder_all: -> { ProcessFinder.find_all },
        process_finder: ProcessFinder.method(:find_pid),
        git_branch: ->(dir) { GitBranch.for(dir) },
        proc_stats: ProcStats.new,
        killer: ->(pid, signal) { Process.kill(signal, pid) },
        snapshot: false)
        @snapshot = snapshot
        @store = store
        @cost_calculator = cost_calculator
        @pricing_table = pricing_table
        @screen = screen
        @theme = theme
        @active_threshold_minutes = active_threshold_minutes
        @refresh_seconds = refresh_seconds
        @clock = clock
        @read_key = read_key || Input::Terminal.new(in_stream: in_stream)
        @process_finder_all = process_finder_all
        @process_finder = process_finder
        @git_branch = git_branch
        @proc_stats = proc_stats
        @killer = killer

        @state = State.new
        @sessions = []
        @all_sessions = []
        @previous_totals = {}
      end

      def run
        @screen.enter
        tick(@clock.call, force: true)
        return if @snapshot

        loop do
          key = @read_key.read_key(@refresh_seconds)
          now = @clock.call
          case key
          when :timeout then tick(now)
          when :quit then break
          else
            break if handle_key(key, now)

            draw(now)
          end
        end
      ensure
        @screen.exit
      end

      private

      def tick(now, force: false)
        @sessions = refresh_and_match(now)
        record_token_deltas(@sessions)
        visible = @state.visible(@sessions, cost_for: cost_lookup)
        @state.sync_selection(visible)
        draw(now, force: force)
      end

      # Per-tick token delta per session (floored at 0, in case of a
      # transient under-read from a concurrently-written log file) —
      # what the table's CPU-HIST-style throughput sparklines would show
      # for tokens, and what the Timeline view charts.
      def record_token_deltas(sessions)
        sessions.each do |s|
          total = s.total_input_tokens + s.total_output_tokens
          previous = @previous_totals[s.id]
          delta = previous.nil? ? 0 : [total - previous, 0].max
          @previous_totals[s.id] = total
          s.token_history.push(delta)
        end
      end

      def cost_lookup
        ->(session) { @cost_calculator.total_for(session.session).amount.to_f }
      end

      def handle_key(key, now)
        return handle_input_key(key, now) if @state.mode == :input

        action = Keymap.action_for(key, mode: @state.mode)
        return true if action == :quit

        if @state.mode == :confirm
          apply_confirm_action(action, now)
        else
          apply_browse_action(action, now)
        end
        false
      end

      def handle_input_key(key, now)
        action = Keymap.action_for(key, mode: :input)
        case action
        when :commit_input then commit_input(now)
        when :cancel_input then cancel_input
        when :backspace then @state.input_buffer = @state.input_buffer[0..-2].to_s
        when :quit then return true
        else @state.input_buffer << key if key.is_a?(String) && key.length == 1
        end
        false
      end

      def apply_confirm_action(action, now)
        case action
        when :confirm then perform_kill(now)
        when :cancel then cancel_kill
        end
      end

      def apply_browse_action(action, now)
        visible = @state.visible(@sessions, cost_for: cost_lookup)
        case action
        when :up, :left then @state.move_selection(visible, -1)
        when :down, :right then @state.move_selection(visible, 1)
        when :first then @state.selected_id = visible.first&.id
        when :last then @state.selected_id = visible.last&.id
        when :log_scroll_up then @state.log_scroll = [@state.log_scroll - 1, 0].max
        when :log_scroll_down then @state.log_scroll += 1
        when :kill then start_kill(visible, "TERM")
        when :force_kill then start_kill(visible, "KILL")
        when :toggle_pin then @state.toggle_pin(@state.selected_id) if @state.selected_id
        when :purge then do_purge(visible)
        when :cycle_sort then @state.cycle_sort
        when :cycle_group then @state.cycle_group
        when :toggle_log then @state.log_expanded = !@state.log_expanded
        when :cycle_theme then cycle_theme
        when :open then do_open
        when :filter then start_input(:filter, @state.filter_text)
        when :search then start_input(:search, @state.search_text)
        when :export then start_input(:export, default_export_path)
        when :kill_all then start_input(:kill_all, "")
        when :help then @state.view = :help
        when :view_dash then @state.view = :dash
        when :view_timeline then @state.view = :timeline
        when :view_history then @state.view = :history
        when :view_heatmap then @state.view = :heatmap
        when :refresh then tick(now)
        when nil then nil
        else @state.status_message = "'#{action}' isn't wired up yet"
        end
      end

      def start_kill(visible, signal)
        session = visible.find { |s| s.id == @state.selected_id }
        return unless session && !session.dead?

        @state.pending_kill_id = session.id
        @state.pending_kill_signal = signal
        @state.mode = :confirm
      end

      def cancel_kill
        @state.pending_kill_id = nil
        @state.mode = :browse
      end

      def perform_kill(now)
        session = @sessions.find { |s| s.id == @state.pending_kill_id }
        signal = @state.pending_kill_signal
        @state.mode = :browse
        @state.pending_kill_id = nil
        return unless session

        pid = @process_finder.call(session.file_path)
        if pid
          @killer.call(pid, signal)
          @state.status_message = "Sent SIG#{signal} to process #{pid} (session #{session.short_id})."
        else
          @state.status_message = "Could not find a running process for session #{session.short_id}."
        end
        # A kill doesn't touch the log file's mtime, so the session would
        # otherwise keep showing as active/live until the next full
        # refresh — re-scan /proc right now so it reads as dead on the
        # very next frame instead of waiting out the refresh interval.
        rematch_all(@sessions)
        draw(now)
      rescue Errno::ESRCH
        @state.status_message = "Process for session #{session.short_id} was already gone."
        draw(now)
      end

      def do_purge(visible)
        count = visible.count(&:dead?)
        @state.purge_all_dead(visible)
        @state.status_message = "Purged #{count} dead session(s)."
      end

      def cycle_theme
        @theme = @theme.with_preset(@theme.next_preset)
        @state.theme_preset = @theme.preset
      end

      def do_open
        session = @sessions.find { |s| s.id == @state.selected_id }
        return unless session

        command = "claude --resume #{session.id}"
        # [text].pack("m0") is core Ruby (Array#pack), not the `base64`
        # library — `require "base64"` would work on Ruby <= 3.3 but
        # raise on 3.4+, where base64 became a bundled (non-default) gem
        # rather than a gem Ruby always ships with. Same reasoning this
        # project already applies to CSV export (see docs/decisions.md).
        @screen.write_raw("\e]52;c;#{[command].pack("m0")}\a")
        @state.status_message = "Resume command copied to clipboard: #{command}"
      end

      def start_input(purpose, prefill)
        @state.mode = :input
        @state.input_purpose = purpose
        @state.input_buffer = prefill.to_s.dup
      end

      def cancel_input
        @state.mode = :browse
        @state.input_purpose = nil
        @state.input_buffer = +""
      end

      def commit_input(now)
        purpose = @state.input_purpose
        buffer = @state.input_buffer.dup
        @state.mode = :browse
        @state.input_purpose = nil
        @state.input_buffer = +""

        case purpose
        when :filter then @state.filter_text = buffer
        when :search then commit_search(buffer)
        when :export then do_export(buffer, now)
        when :kill_all then do_kill_all(buffer, now)
        end
      end

      def commit_search(buffer)
        @state.search_text = buffer
        visible = @state.visible(@sessions, cost_for: cost_lookup)
        found = @state.jump_to_next_match(visible)
        @state.status_message = found ? nil : "No match for \"#{buffer}\""
      end

      def default_export_path
        "./aiwatch-export-#{@clock.call.strftime("%Y%m%d-%H%M%S")}.json"
      end

      def do_export(path, now)
        path = default_export_path if path.to_s.strip.empty?
        visible = @state.visible(@sessions, cost_for: cost_lookup)
        Exporter.write(visible, cost_calculator: @cost_calculator, path: path, now: now, active_threshold_minutes: @active_threshold_minutes)
        @state.status_message = "Exported #{visible.length} session(s) to #{path}"
      rescue => e
        @state.status_message = "Export failed: #{e.message}"
      end

      def do_kill_all(typed, now)
        unless typed.strip.downcase == "yes"
          @state.status_message = "Kill all canceled (type exactly \"yes\" to confirm)."
          return
        end

        visible = @state.visible(@sessions, cost_for: cost_lookup)
        killable = visible.reject(&:dead?)
        killed = killable.count { |session| attempt_kill(session) }
        rematch_all(@sessions)
        @state.status_message = "Sent SIGTERM to #{killed}/#{killable.length} active session(s)."
        draw(now)
      end

      def attempt_kill(session)
        pid = @process_finder.call(session.file_path)
        return false unless pid

        @killer.call(pid, "TERM")
        true
      rescue Errno::ESRCH
        false
      end

      def refresh_and_match(now)
        sessions = @store.refresh(priority_id: @state.selected_id)
        @all_sessions = sessions
        eligible = sessions.select { |s| s.active?(now: now, threshold_minutes: @active_threshold_minutes) }
        rematch_all(eligible)
        eligible
      end

      def rematch_all(sessions)
        top_level, subagents = sessions.partition { |s| !s.subagent? }
        rematch_processes(top_level, subagents)
        mark_subagents_active(subagents)
      end

      # Subagents don't correspond to a distinguishable OS process at
      # all reliably (no cmdline argument ties one back to its agentId),
      # so no /proc matching is attempted for them — being in `eligible`
      # already means their own file's mtime is within the active
      # window, which is the only liveness signal available for one.
      def mark_subagents_active(subagents)
        subagents.each { |s| s.dead = false }
      end

      # One /proc scan for every top-level session, rather than one per
      # session — this is exactly the cost the old single-session
      # ProcessFinder call would have paid N times per tick. A top-level
      # session whose own PID can't be matched (ambiguous: two terminals
      # opened from the same directory is common) is NOT necessarily
      # dead — it reads as still active if it has a subagent with recent
      # activity of its own, since that's real, current work regardless
      # of whether the parent's own process could be pinned down.
      def rematch_processes(top_level, subagents)
        procs = @process_finder_all.call
        by_slug = procs.group_by { |p| p[:slug] }
        # Hash used as a set (Array#to_set needs `require "set"`, and
        # this project checks stdlib availability carefully after the
        # base64-on-Ruby-3.4 lesson — see docs/decisions.md).
        active_via_subagent = subagents.each_with_object({}) { |s, h| h[s.parent_id] = true }
        matched_pids = []

        top_level.each do |session|
          slug = File.basename(File.dirname(session.file_path))
          candidates = by_slug[slug] || []
          if candidates.length == 1
            apply_match(session, candidates.first)
            matched_pids << candidates.first[:pid]
          else
            session.pid = nil
            session.dead = !active_via_subagent.key?(session.id)
          end
        end

        sample_process_stats(top_level, matched_pids)
      end

      def apply_match(session, proc_entry)
        session.pid = proc_entry[:pid]
        session.dead = false
        branch = @git_branch.call(proc_entry[:cwd])
        session.branch = branch if branch
      end

      def sample_process_stats(sessions, pids)
        readings = @proc_stats.sample(pids)
        sessions.each do |session|
          reading = session.pid && readings[session.pid]
          next unless reading

          session.cpu_percent = reading.cpu_percent
          session.mem_percent = reading.mem_percent
          session.cpu_history.push(reading.cpu_percent || 0)
          session.mem_history.push(reading.mem_percent || 0)
        end
      end

      def draw(now, force: false)
        cols, lines = @screen.size
        canvas = Tui::Canvas.new(width: cols, height: lines)
        regions = Tui::Layout.compute(cols, lines)
        force ||= @screen.resized?

        if regions.too_small
          draw_too_small(canvas, cols, lines)
        else
          draw_view(canvas, regions, now)
        end

        @screen.flush(canvas.to_lines, force: force)
      end

      def draw_view(canvas, regions, now)
        case @state.view
        when :help then Views::Help.draw(canvas, regions, theme: @theme)
        when :timeline then Views::Timeline.draw(canvas, regions, theme: @theme, sessions: @state.visible(@sessions, cost_for: cost_lookup), now: now)
        when :history then Views::History.draw(canvas, regions, theme: @theme, all_sessions: @all_sessions, active_sessions: @sessions, cost_calculator: @cost_calculator, now: now)
        when :heatmap then Views::Heatmap.draw(canvas, regions, theme: @theme, sessions: @all_sessions, cost_calculator: @cost_calculator, now: now)
        else draw_dash(canvas, regions, now)
        end
        Widgets::Footer.draw(canvas, regions.footer, theme: @theme, text: footer_text)
      end

      def draw_dash(canvas, regions, now)
        visible = @state.visible(@sessions, cost_for: cost_lookup)
        selected = visible.find { |s| s.id == @state.selected_id }
        context_limit_for = ->(model) { model && @pricing_table.context_limit_for(model) }

        Widgets::TitleBar.draw(canvas, regions.title, theme: @theme, title: "AIWATCH — AI Agent Terminal Operations Panel")
        Widgets::StatsBar.draw(canvas, regions.stats, theme: @theme, sessions: visible, now: now, total_cost: total_cost(visible))
        Widgets::SessionTable.draw(canvas, regions.table, theme: @theme, sessions: visible, selected_id: @state.selected_id,
          cost_calculator: @cost_calculator, context_limit_for: context_limit_for, now: now)
        if regions.sidebar
          Widgets::Sidebar.draw(canvas, regions.sidebar, theme: @theme, session: selected, cost_calculator: @cost_calculator,
            context_limit_for: context_limit_for, now: now)
        end
        Widgets::SessionLog.draw(canvas, regions.log, theme: @theme, session: selected) if regions.log
      end

      def draw_too_small(canvas, cols, lines)
        message = "Terminal too small — need #{Tui::Layout::MIN_WIDTH}x#{Tui::Layout::MIN_HEIGHT} (now #{cols}x#{lines})"
        row = [lines / 2, 0].max
        col = [(cols - message.length) / 2, 0].max
        canvas.write(row, col, message, max: cols)
      end

      def total_cost(sessions)
        sessions.sum { |s| @cost_calculator.total_for(s.session).amount.to_f }
      end

      def footer_text
        case @state.mode
        when :confirm then confirm_footer_text
        when :input then input_footer_text
        else @state.status_message || Keymap.footer_text
        end
      end

      def confirm_footer_text
        session = @sessions.find { |s| s.id == @state.pending_kill_id }
        verb = (@state.pending_kill_signal == "KILL") ? "force-kill (SIGKILL)" : "kill (SIGTERM)"
        "Really #{verb} session #{session&.short_id}? y = confirm, n/Esc = cancel"
      end

      def input_footer_text
        label = {
          filter: "Filter", search: "Search", export: "Export to path",
          kill_all: "Type \"yes\" to SIGTERM every visible active session"
        }.fetch(@state.input_purpose, "Input")
        "#{label}: #{@state.input_buffer}▌  (Enter confirms, Esc cancels)"
      end
    end
  end
end
