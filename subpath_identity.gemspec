# frozen_string_literal: true

require_relative "lib/subpath_identity/version"

Gem::Specification.new do |spec|
  spec.name = "subpath_identity"
  spec.version = SubpathIdentity::VERSION
  spec.authors = ["Raghu Betina"]
  spec.email = ["raghu@firstdraft.com"]

  spec.summary = "Shared identity cookie and origin verification for path-based multi-app Rails deployments."
  spec.description = "A small encrypted, explicitly allowlisted cookie that independently-deployed " \
    "apps behind one path-based edge router (mydomain.com/app1, mydomain.com/app2) can read and " \
    "write to share identity, plus Rack middleware verifying that requests actually came through " \
    "the router rather than being sent directly to a public origin URL."
  spec.homepage = "https://github.com/raghubetina/subpath_identity"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .standard.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "railties", ">= 7.0"
  spec.add_dependency "rack", ">= 2.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
