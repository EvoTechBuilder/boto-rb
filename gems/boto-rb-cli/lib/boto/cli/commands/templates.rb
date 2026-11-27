# frozen_string_literal: true

module Boto
  module CLI
    module Commands
      # Named Templates here; ::Boto::Templates is the registry, referenced with the leading :: to avoid the clash.
      class Templates < Command
        SUMMARY = "List template gems and add one to the Gemfile"
        USAGE = "Usage: boto templates <list|install GEM>"
        POSITION = 11
        LIST = "list"
        INSTALL = "install"
        GEMFILE_NAME = "Gemfile"
        GEM_NAME_FORMAT = /\A[a-z0-9][a-z0-9_-]*\z/
        COLUMN_GAP = "   "
        HTTP_LABEL = "http"
        NOT_AVAILABLE_NOTE = ", not available yet"
        # shortcut: the official files are only checked by folder name, not by content, upgrade if that gets ambiguous
        DEFAULT_OFFICIAL_ROOT = Generator::TEMPLATES_ROOT

        def initialize(argv, out:, err:, cwd:, official_root: DEFAULT_OFFICIAL_ROOT)
          super(argv, out: out, err: err, cwd: cwd)
          @official_root = official_root
        end

        def call
          subcommand, *rest = argv
          case subcommand
          when LIST then list(rest)
          when INSTALL then install(rest)
          else raise Error, USAGE
          end
        end

        private

        def list(rest)
          raise Error, USAGE unless rest.empty?

          rows = ::Boto::Templates.all.map { |template| row(template) }
          table(rows).each { out.puts _1 }
          SUCCESS
        end

        def install(args)
          gem_name, *extra = args
          raise Error, USAGE if gem_name.nil? || !extra.empty?

          check_gem_name!(gem_name)
          add_to_gemfile(gem_name)
          out.puts "update #{GEMFILE_NAME}"
          out.puts "Next: bundle install"
          out.puts "Then: boto templates list"
          SUCCESS
        end

        def check_gem_name!(gem_name)
          raise Error, %(invalid gem name "#{gem_name}") unless GEM_NAME_FORMAT.match?(gem_name)
        end

        # Plain append: the Gemfile is the user's file, so nothing is rewritten, only a line is added at the end.
        def add_to_gemfile(gem_name)
          path = gemfile_path
          content = File.read(path)
          raise Error, "#{gem_name} is already in the Gemfile" if content.match?(declaration_pattern(gem_name))

          File.write(path, separator(content) + declaration(gem_name), mode: "a")
        end

        def gemfile_path
          path = File.join(cwd, GEMFILE_NAME)
          raise Error, "Gemfile not found in #{cwd}" unless File.file?(path)

          path
        end

        def declaration_pattern(gem_name) = /^\s*gem\s+["']#{Regexp.escape(gem_name)}["']/

        def declaration(gem_name) = %(gem "#{gem_name}"\n)

        def separator(content) = content.empty? || content.end_with?("\n") ? "" : "\n"

        def row(template)
          [template.name.to_s, "#{template.folder}/", template.http ? HTTP_LABEL : "", source_label(template)]
        end

        def source_label(template)
          note = available?(template) ? "" : NOT_AVAILABLE_NOTE
          "(#{template.source}#{note})"
        end

        def available?(template)
          !template.files.nil? || File.directory?(File.join(@official_root, template.name.to_s))
        end

        # Every column but the last is padded to its widest cell; the last one is left as is, so no trailing spaces.
        def table(rows)
          widths = rows.transpose.map { |column| column.map(&:size).max }
          rows.map do |cells|
            padded = cells[0...-1].each_with_index.map { |cell, index| cell.ljust(widths[index]) }
            [*padded, cells.last].join(COLUMN_GAP)
          end
        end
      end
    end
  end
end
