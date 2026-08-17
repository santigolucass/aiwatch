# frozen_string_literal: true

require "json"
require_relative "tail_reader"
require_relative "live_session"
require_relative "adapters/line_folder"

module Aiwatch
  # The live dashboard's incremental index over the same session files
  # `list`/`daily`/`show` read in full every time. Where those commands
  # re-parse a whole file on every call (fine for a one-shot command),
  # SessionStore keeps a TailReader per file and only reads the bytes
  # appended since the last #refresh — the difference between re-parsing
  # ~250MB every 2s and touching a handful of stat() calls most ticks.
  #
  # A brand-new file larger than `tail_bytes` is read from its tail
  # first (so the dashboard has *something* to show immediately) rather
  # than blocking on a full parse; the skipped leading portion is then
  # backfilled a bounded chunk at a time across subsequent #refresh
  # calls, prioritizing whichever session is currently selected. Until a
  # session's backfill completes, its LiveSession#totals_partial? is
  # true — totals are real but incomplete.
  class SessionStore
    Cursor = Struct.new(:tail_reader, :session, :seen_message_ids, :live_session, :backfill)
    Backfill = Struct.new(:cursor_pos, :done, :carry)

    DEFAULT_TAIL_BYTES = 256 * 1024
    # Measured against a real ~250MB/34-file corpus: at 512KB, full
    # backfill of every session converges in well under a second total,
    # with no single tick costing more than ~10ms — imperceptible against
    # a multi-second render interval. A conservative default like 32KB
    # technically also converges, just over many minutes instead.
    DEFAULT_BACKFILL_BUDGET_BYTES = 512 * 1024

    def initialize(adapter:, tail_bytes: DEFAULT_TAIL_BYTES, backfill_budget_bytes: DEFAULT_BACKFILL_BUDGET_BYTES)
      @adapter = adapter
      @tail_bytes = tail_bytes
      @backfill_budget_bytes = backfill_budget_bytes
      @cursors = {}
      @last_stat = {}
    end

    # Returns Array<LiveSession>, one per discovered session file, having
    # read only what changed since the last call. priority_id: a session
    # id whose backfill (if any is pending) should advance this tick
    # ahead of any other pending backfill.
    def refresh(priority_id: nil)
      paths = @adapter.session_files
      paths.each { |path| refresh_one(path) }
      prune_missing(paths)
      run_backfill(priority_id)
      @cursors.values.map(&:live_session)
    end

    private

    def refresh_one(path)
      stat = File.stat(path)
      cached = @last_stat[path]
      return if cached && cached[0] == stat.mtime && cached[1] == stat.size

      cursor = @cursors[path] ||= build_cursor(path)
      lines = cursor.tail_reader.read_new_lines(stat, tail_bytes: @tail_bytes)
      @last_stat[path] = [stat.mtime, stat.size]
      return unless lines

      # A rotation/truncation mid-run means the reader's own byte-offset
      # bookkeeping already self-healed, but the Session and dedup hash
      # built from what it served BEFORE the rotation are now stale data
      # from a file that (as far as this cursor is concerned) no longer
      # exists — rebuild them rather than folding fresh content into a
      # stale aggregate and a dedup hash that would wrongly suppress
      # every id it happens to share with the old file's content.
      cursor = rebuild_cursor(path, cursor) if cursor.tail_reader.reset?

      fold_lines(cursor, lines)
      start_backfill(cursor) if cursor.tail_reader.tail_seeked?
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end

    def build_cursor(path)
      id = File.basename(path, ".jsonl")
      session = Session.new(id: id, file_path: path)
      Cursor.new(TailReader.new(path), session, {}, LiveSession.new(session: session), nil)
    end

    def rebuild_cursor(path, old_cursor)
      session = Session.new(id: old_cursor.session.id, file_path: path)
      cursor = Cursor.new(old_cursor.tail_reader, session, {}, LiveSession.new(session: session), nil)
      @cursors[path] = cursor
      cursor
    end

    def fold_lines(cursor, lines)
      lines.each do |raw|
        line = raw.strip
        next if line.empty?

        obj = begin
          JSON.parse(line)
        rescue
          cursor.session.note_skipped_line
          next
        end

        cursor.live_session.ingest(obj, cursor.seen_message_ids)
        Adapters::LineFolder.fold_object(cursor.session, cursor.seen_message_ids, obj)
      end
      cursor.live_session.flush_feed!
    end

    def prune_missing(paths)
      (@cursors.keys - paths).each do |stale|
        @cursors.delete(stale)
        @last_stat.delete(stale)
      end
    end

    def start_backfill(cursor)
      cursor.backfill = Backfill.new(cursor.tail_reader.first_read_offset, false, "")
      cursor.live_session.totals_partial = true
    end

    def run_backfill(priority_id)
      candidates = @cursors.values.select { |c| c.backfill && !c.backfill.done }
      return if candidates.empty?

      cursor = candidates.find { |c| c.session.id == priority_id } || candidates.first
      advance_backfill(cursor)
    end

    # Reads backward in fixed-size chunks toward byte 0. Chunk
    # boundaries fall at arbitrary byte offsets, not line boundaries, so
    # each chunk's leading fragment is carried forward (not discarded)
    # and prepended to the NEXT (further back) chunk read — reconstructing
    # exactly the line that boundary split, rather than losing it. Only
    # the very first chunk's end (bf.cursor_pos, established by
    # TailReader's own cold-start seek) and the very last chunk's start
    # (byte 0) are guaranteed-clean boundaries; the ones in between never
    # need to be.
    def advance_backfill(cursor)
      bf = cursor.backfill
      return finish_backfill(cursor) if bf.cursor_pos <= 0

      stop = bf.cursor_pos
      start = [stop - @backfill_budget_bytes, 0].max
      combined = read_chunk(cursor.session.file_path, start, stop) + bf.carry
      pieces = combined.split("\n", -1)
      pieces.pop if pieces.last == ""

      bf.carry = start.zero? ? "" : pieces.shift.to_s
      fold_backfill_lines(cursor, pieces)
      bf.cursor_pos = start
      finish_backfill(cursor) if start.zero?
    rescue Errno::ENOENT, Errno::EACCES
      finish_backfill(cursor)
    end

    def read_chunk(path, start, stop)
      File.open(path, "rb") do |f|
        f.seek(start)
        f.read(stop - start) || ""
      end
    end

    def fold_backfill_lines(cursor, lines)
      lines.each do |raw|
        line = raw.force_encoding(Encoding::UTF_8).scrub.strip
        next if line.empty?

        obj = begin
          JSON.parse(line)
        rescue
          next
        end
        Adapters::LineFolder.fold_object(cursor.session, cursor.seen_message_ids, obj)
      end
    end

    def finish_backfill(cursor)
      cursor.backfill.done = true
      cursor.live_session.totals_partial = false
    end
  end
end
