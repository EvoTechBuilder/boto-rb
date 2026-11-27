# frozen_string_literal: true

module Boto
  module CLI
    # The lines `boto run` prints under its header: one block per gateway, or one line per project without gateways.
    class PortAnnouncement
      GATEWAY_LINE = "Gateway %<name>s on %<url>s"
      PANEL_NAME = "panel"
      PANEL_PATH = "/_boto"
      RANDOM_TAG = " (random)"
      # Services are mounted at /<name>. The CLI does not read the gateway's `prefixes:`, so that path is fixed here.
      COLUMN_GAPS = [2, 3].freeze

      def initialize(result, host:, development:)
        @result = result
        @host = host
        @development = development
      end

      def lines
        return project_lines if result.gateways.empty?

        result.gateways.flat_map { |name, refs| gateway_block(name, refs) }
      end

      private

      attr_reader :result, :host, :development

      def project_lines
        result.ports.map { |name, port| "  #{name}  #{url(port)}" }
      end

      def gateway_block(name, refs)
        port = result.ports.fetch(name)
        rows = refs.map { |ref| service_row(port, ref) }
        rows << [PANEL_NAME, url(port, PANEL_PATH)] if development
        [format(GATEWAY_LINE, name: name, url: url(port)), *table(rows)]
      end

      def service_row(gateway_port, ref)
        tag = result.random.include?(ref) ? RANDOM_TAG : ""
        [ref, url(gateway_port, "/#{ref}"), "#{url(result.ports.fetch(ref))}#{tag}"]
      end

      # The last cell of a row is not padded, so rows with fewer cells end without trailing spaces.
      def table(rows)
        widths = Array.new(COLUMN_GAPS.size) { |column| rows.map { |cells| cells[column].size }.max }
        rows.map do |cells|
          "  #{cells.each_with_index.map { |cell, column| pad(cell, cells, column, widths) }.join}"
        end
      end

      def pad(cell, cells, column, widths)
        return cell if column == cells.size - 1

        cell.ljust(widths[column] + COLUMN_GAPS[column])
      end

      def url(port, path = "")
        "http://#{host}:#{port}#{path}"
      end
    end
  end
end
