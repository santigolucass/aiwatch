require_relative "lib/aiwatch/version"

Gem::Specification.new do |spec|
  spec.name = "aiwatch"
  spec.version = Aiwatch::VERSION
  spec.authors = ["Lucas Santiago"]
  spec.email = ["lucas.stgom@gmail.com"]

  spec.summary = "An htop for your local AI coding agents"
  spec.description = <<~DESC
    aiwatch inspects local session logs from AI coding agents (Claude Code in v0.1)
    and reports token usage and estimated cost per session, per day, and live as
    agents run — without sending anything anywhere.
  DESC
  spec.homepage = "https://github.com/santigolucass/aiwatch"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "standard", "~> 1.0"
end
