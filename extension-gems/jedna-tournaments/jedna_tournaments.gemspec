# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'jedna_tournaments'
  spec.version = '0.1.0'
  spec.authors = ['Jedna Contributors']
  spec.email = ['']

  spec.summary = 'Tournament infrastructure for Jedna card game agents'
  spec.description = 'Provides tournament runners and agent adapters for running automated Jedna games. ' \
                     'Supports multiple agent communication protocols and tournament formats.'
  spec.homepage = 'https://github.com/kaiks/jedna'
  spec.license = 'PolyForm-Noncommercial-1.0.0'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/kaiks/jedna'

  spec.files = Dir.chdir(__dir__) do
    Dir['lib/**/*', 'LICENSE', 'README.md', 'examples/**/*'].select { |f| File.file?(f) }
  end
  spec.bindir = 'exe'
  spec.executables = []
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'jedna', '~> 0.1'
  spec.add_dependency 'json', '~> 2.0'
  spec.add_dependency 'timeout', '~> 0.4'

  # Development dependencies
  spec.add_development_dependency 'debug', '~> 1.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.21'
end
