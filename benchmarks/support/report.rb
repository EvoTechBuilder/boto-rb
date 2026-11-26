# frozen_string_literal: true

module BenchReport
  HEADERS = ["framework", "scenario", "req/s", "p99 ms", "allocs/req"].freeze

  def self.table(frameworks)
    rows = frameworks.flat_map do |framework, scenarios|
      scenarios.map { |scenario, numbers| [framework, scenario, numbers["rps"], numbers["p99_ms"], numbers["allocations"]] }
    end
    format_rows([HEADERS, *rows.map { |row| row.map(&:to_s) }])
  end

  def self.comparison(rows)
    headers = ["scenario", "metric", "baseline", "current", "change", "regression"]
    body = rows.map do |row|
      [row.scenario, row.metric, row.baseline.to_s, row.current.to_s, percent(row.change), row.regressed ? "SIM" : "não"]
    end
    format_rows([headers, *body])
  end

  def self.percent(change)
    return "inf" if change.infinite?

    format("%+.1f%%", change * 100)
  end

  def self.format_rows(rows)
    widths = rows.transpose.map { |column| column.map(&:length).max }
    rows.map { |row| row.zip(widths).map { |cell, width| cell.ljust(width) }.join("  ").rstrip }.join("\n")
  end
end
