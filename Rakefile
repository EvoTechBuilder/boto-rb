# frozen_string_literal: true

GEM_DIRS = %w[gems/boto gems/boto-cli].freeze

task default: :test

desc "Run the test suite of every gem"
task :test do
  GEM_DIRS.each do |dir|
    Dir.chdir(File.join(__dir__, dir)) { sh "bundle exec rake test" }
  end
end
