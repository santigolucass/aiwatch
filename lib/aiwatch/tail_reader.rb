# frozen_string_literal: true

module Aiwatch
  # Incremental line reader: reads only the bytes appended to a file since
  # the last call, keeping any trailing partial (no-newline-yet) line
  # buffered rather than ever returning a torn line. This is what lets
  # SessionStore refresh a ~250MB corpus every tick by touching only the
  # handful of files that actually changed, and only the bytes each one
  # grew by — never re-parsing what's already been read.
  class TailReader
    attr_reader :offset, :ino, :first_read_offset

    def initialize(path)
      @path = path
      @offset = 0
      @ino = nil
      @partial = +""
      @first_read_offset = nil
      @reset_occurred = false
      @tail_seeked_this_read = false
    end

    # True if THIS call detected truncation/rotation and threw away all
    # prior offset/inode state. A one-shot signal, cleared at the start
    # of every call — the caller must react on the same tick it fires:
    # this reader's own byte-offset bookkeeping is self-healing, but
    # whatever aggregate state (a Session, a dedup hash) the caller built
    # from what this reader previously served is now stale and must be
    # rebuilt from scratch by the caller, not just carried forward.
    def reset?
      @reset_occurred
    end

    # True if THIS call performed the cold-start tail-seek (skipping the
    # file's leading portion). A one-shot signal for the same reason as
    # #reset? — it's how a caller knows "there is a leading portion of
    # this file I haven't read and may want to backfill", without it
    # re-firing on every later, ordinary incremental read.
    def tail_seeked?
      @tail_seeked_this_read
    end

    # stat: a File::Stat for @path, fetched by the caller — SessionStore
    # already needs one per tick to decide whether to read at all, so
    # this avoids statting the file twice.
    #
    # tail_bytes: on this reader's very first read, if the file is
    # larger than tail_bytes, seek to the last tail_bytes instead of the
    # top — the cold-start optimization for multi-megabyte logs, so a
    # dashboard doesn't block for tens of seconds parsing a corpus it's
    # only just discovered. Ignored on every later call. The byte offset
    # this landed on is recorded as #first_read_offset, so a caller that
    # wants the (skipped) leading portion of the file can backfill it
    # separately, in its own time.
    #
    # Returns Array<String> of complete new lines (newline stripped), or
    # nil if the file could not be opened.
    def read_new_lines(stat, tail_bytes: nil)
      @reset_occurred = false
      @tail_seeked_this_read = false
      reset! if rotated_or_truncated?(stat)

      File.open(@path, "rb") do |f|
        seek_for_cold_start(f, stat, tail_bytes) if cold_start?
        f.seek(@offset)
        chunk = f.read([stat.size - @offset, 0].max) || ""
        @offset = f.pos
        @ino = stat.ino
        extract_lines(chunk)
      end
    rescue Errno::ENOENT, Errno::EACCES, IOError
      nil
    end

    private

    def cold_start?
      @offset.zero? && @ino.nil?
    end

    def rotated_or_truncated?(stat)
      (!@ino.nil? && stat.ino != @ino) || stat.size < @offset
    end

    def reset!
      @offset = 0
      @ino = nil
      @partial = +""
      @first_read_offset = nil
      @reset_occurred = true
    end

    def seek_for_cold_start(f, stat, tail_bytes)
      @first_read_offset = 0
      return unless tail_bytes && stat.size > tail_bytes

      @offset = stat.size - tail_bytes
      f.seek(@offset)
      f.gets # discard the (likely torn) partial line at the seek point
      @offset = f.pos
      @first_read_offset = @offset
      @tail_seeked_this_read = true
    end

    def extract_lines(chunk)
      return [] if chunk.empty? && @partial.empty?

      @partial << chunk
      lines = @partial.split("\n", -1)
      @partial = lines.pop || +""
      lines.map { |l| l.force_encoding(Encoding::UTF_8).scrub }
    end
  end
end
