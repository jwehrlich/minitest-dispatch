# frozen_string_literal: true

require_relative "lib/minitest/dispatch/version"

Gem::Specification.new do |spec|
  spec.name = "minitest-dispatch"
  spec.version = Minitest::Dispatch::VERSION
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.summary     = "Distributed testing for minitest"
  spec.description = "Distributed testing for minitest"
  spec.authors     = ["Jason W. Ehrlich"]
  spec.email       = ["jwehrlich@outlook.com"]
  spec.license     = "GNU Lesser General Public License v3.0"

  spec.homepage = "https://github.com/jwehrlich/minitest-dispatch"
  spec.metadata["documentation_uri"] = "https://github.com/jwehrlich/minitest-dispatch"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end

  spec.required_ruby_version = ">= 2.6.0"
  spec.add_dependency "eventmachine", "~>1.0.7"
  spec.add_dependency "minitest",     "~>5.10.0"
  spec.add_dependency "nokogiri",     "~>1.13.10"
  spec.add_dependency "os",           "~>0.9.6"
  spec.add_dependency "rake"

  spec.add_development_dependency "byebug"
  spec.add_development_dependency "mocha"
  spec.add_development_dependency "rubocop"

  spec.require_paths = ["lib"]
  spec.bindir = "bin"
  spec.executables.push("minitest-dispatch")
end
