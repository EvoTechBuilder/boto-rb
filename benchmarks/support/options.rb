# frozen_string_literal: true

require "optparse"

module BenchOptions
  Options = Struct.new(:quick, :save_baseline, :compare, keyword_init: true)

  def self.parse(argv)
    options = Options.new(quick: false, save_baseline: false, compare: false)
    OptionParser.new do |parser|
      parser.on("--quick", "1 rodada e carga menor, para testes locais") { options.quick = true }
      parser.on("--save-baseline", "Grava results/baseline.json") { options.save_baseline = true }
      parser.on("--compare", "Compara o boto com results/baseline.json") { options.compare = true }
    end.parse!(argv)
    options
  end
end
