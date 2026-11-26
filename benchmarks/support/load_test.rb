# frozen_string_literal: true

require "open3"

# Picks wrk when it is on PATH, otherwise ab. Each tool reports { rps:, p99_ms: }.
module BenchLoadTest
  class Error < StandardError; end

  def self.build(quick:, path: ENV.fetch("PATH", ""))
    tool_class = executable?(Wrk::NAME, path) ? Wrk : Ab
    tool_class.new(quick: quick)
  end

  def self.executable?(name, path)
    path.split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, name)) }
  end

  def self.capture(command)
    output, status = Open3.capture2(*command, err: File::NULL)
    raise Error, "#{command.first} falhou (status #{status.exitstatus})" unless status.success?

    output
  end

  def self.metric(output, pattern)
    match = output.match(pattern)
    raise Error, "métrica #{pattern.source} não encontrada na saída da ferramenta" unless match

    match
  end

  class Ab
    NAME = "ab"
    CONCURRENCY = 50
    FULL = { requests: 20_000, warmup: 2_000 }.freeze
    QUICK = { requests: 2_000, warmup: 200 }.freeze
    RPS_PATTERN = /^Requests per second:\s+([\d.]+)/
    P99_PATTERN = /^\s*99%\s+(\d+)/

    def initialize(quick:)
      @profile = quick ? QUICK : FULL
    end

    def name = NAME

    def warm_up(url)
      BenchLoadTest.capture(command(url, @profile[:warmup]))
      nil
    end

    def measure(url)
      parse(BenchLoadTest.capture(command(url, @profile[:requests])))
    end

    def command(url, requests)
      ["ab", "-k", "-n", requests.to_s, "-c", CONCURRENCY.to_s, url]
    end

    def parse(output)
      {
        rps: Float(BenchLoadTest.metric(output, RPS_PATTERN)[1]),
        p99_ms: Float(BenchLoadTest.metric(output, P99_PATTERN)[1])
      }
    end
  end

  class Wrk
    NAME = "wrk"
    THREADS = 2
    CONNECTIONS = 50
    FULL = { duration: "10s", warmup: "2s" }.freeze
    QUICK = { duration: "3s", warmup: "1s" }.freeze
    RPS_PATTERN = %r{^Requests/sec:\s+([\d.]+)}
    P99_PATTERN = /^\s*99%\s+([\d.]+)(us|ms|s)\s*$/
    MS_PER_UNIT = { "us" => 0.001, "ms" => 1.0, "s" => 1000.0 }.freeze

    def initialize(quick:)
      @profile = quick ? QUICK : FULL
    end

    def name = NAME

    def warm_up(url)
      BenchLoadTest.capture(command(url, @profile[:warmup]))
      nil
    end

    def measure(url)
      parse(BenchLoadTest.capture(command(url, @profile[:duration])))
    end

    def command(url, duration)
      ["wrk", "-t#{THREADS}", "-c#{CONNECTIONS}", "-d#{duration}", "--latency", url]
    end

    def parse(output)
      match = BenchLoadTest.metric(output, P99_PATTERN)
      {
        rps: Float(BenchLoadTest.metric(output, RPS_PATTERN)[1]),
        p99_ms: Float(match[1]) * MS_PER_UNIT.fetch(match[2])
      }
    end
  end
end
