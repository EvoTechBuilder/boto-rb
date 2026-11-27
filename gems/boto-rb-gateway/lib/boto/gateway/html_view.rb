# frozen_string_literal: true

require "erb"

module Boto
  module Gateway
    # Renders the panel page from panel.html.erb. Every value goes through h (ERB::Util.html_escape).
    class HtmlView
      include ERB::Util

      HEALTH_LABELS = { ready: "Ready", failing: "Not ready", none: "No health check" }.freeze

      # Read as UTF-8 whatever the locale is: the page contains non-ASCII characters.
      def self.template = ERB.new(File.read(Panel::TEMPLATE_FILE, encoding: Encoding::UTF_8), trim_mode: "-")

      def initialize(template)
        @template = template
      end

      def render(page)
        @template.result(binding)
      end

      private

      def plural(count, word) = "#{count} #{count == 1 ? word : "#{word}s"}"

      def health_label(status) = HEALTH_LABELS.fetch(status)

      def verb_class(verb) = "verb verb--#{verb.downcase}"
    end
  end
end
