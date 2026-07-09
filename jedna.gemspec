# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "jedna"
  spec.version = "0.1.0"
  spec.authors = ["Karol Lewcio"]
  spec.email = [""]

  spec.summary = "A card game engine based on the popular UNO! game"
  spec.description = "Jedna! is a flexible, extensible card game engine that implements some of the rules of UNO!. " \
                     "It provides clean interfaces for notifications, rendering, persistence, and player identity " \
                     "to enable use in various contexts including IRC bots, web applications, and CLI tools."
  spec.homepage = "https://github.com/kaiks/jedna"
  spec.license = "PolyForm-Noncommercial-1.0.0"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage

  spec.files = Dir.chdir(__dir__) do
    Dir['lib/**/*', 'LICENSE', 'README.md', 'automated_play.md', 'game_rules.md'].select { |file| File.file?(file) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "monitor", "~> 0.1"

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "bigdecimal", "~> 3.1"
end
