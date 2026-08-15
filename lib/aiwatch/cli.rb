# frozen_string_literal: true

module Aiwatch
  class CLI
    COMMANDS = %w[list daily show live].freeze

    def self.run(argv)
      new.run(argv.dup)
    end

    def run(argv)
      return version! if %w[-v --version].include?(argv.first)
      return help! if %w[-h --help].include?(argv.first)

      command = COMMANDS.include?(argv.first) ? argv.shift : "list"
      command_class(command).new(argv).run
    rescue OptionParser::ParseError => e
      warn "aiwatch: #{e.message}"
      1
    end

    private

    def command_class(name)
      case name
      when "list" then Commands::List
      when "daily" then Commands::Daily
      when "show" then Commands::Show
      when "live" then Commands::Live
      end
    end

    def version!
      puts "aiwatch #{Aiwatch::VERSION}"
      0
    end

    def help!
      puts <<~HELP
        Usage: aiwatch [command] [options]

        Commands:
          list      Recent sessions (default command)
          daily     Tokens and cost aggregated by day
          show ID   Detail for one session (uuid or prefix)
          live      Auto-refreshing view of active sessions

        Run `aiwatch <command> --help` for command-specific options.

        Global options:
          --dir DIR   Override the Claude Code logs directory
          --json      Emit JSON instead of a table (list, daily, show)
          -v, --version
          -h, --help
      HELP
      0
    end
  end
end
