# frozen_string_literal: true

require "json"
require "fileutils"

module BenchResults
  def self.median(values)
    sorted = values.sort
    middle = sorted.size / 2
    return sorted[middle] if sorted.size.odd?

    (sorted[middle - 1] + sorted[middle]) / 2.0
  end

  # samples: one { rps:, p99_ms: } per round
  def self.summarize(samples, allocations:)
    {
      "rps" => median(samples.map { |sample| sample[:rps] }).round(1),
      "p99_ms" => median(samples.map { |sample| sample[:p99_ms] }).round(2),
      "allocations" => allocations.round(2)
    }
  end

  def self.document(frameworks, tool:, ruby:, yjit:)
    frameworks.merge("tool" => tool, "ruby" => ruby, "yjit" => yjit)
  end

  def self.write(path, document)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#{JSON.pretty_generate(document)}\n")
  end

  def self.read(path)
    JSON.parse(File.read(path))
  end
end
