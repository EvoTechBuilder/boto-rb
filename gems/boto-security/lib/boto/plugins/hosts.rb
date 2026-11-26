# frozen_string_literal: true

module Boto
  module Plugins
    # Blocks requests whose Host header is not on the allow list, which stops DNS rebinding.
    class Hosts < Boto::Plugin
      scope :global

      DEVELOPMENT_HOSTS = %w[localhost 127.0.0.1 ::1].freeze
      SUFFIX_PREFIX = "."
      PORT_SUFFIX = /:\d+\z/
      BRACKETED_IPV6 = /\A\[([^\]]+)\](?::\d+)?\z/
      FORBIDDEN_DETAIL = "host not allowed"

      def call(env, app)
        return app.call(env) if allowed?(host_from(env))

        Boto::Error::Forbidden.new(FORBIDDEN_DETAIL).to_response
      end

      private

      def configure(allow: [])
        entries = normalize(allow)
        raise ArgumentError, "hosts: allow is required outside development" if entries.empty? && !development?

        entries += DEVELOPMENT_HOSTS if development?
        @exact_hosts, @suffixes = split(entries)
      end

      def normalize(allow)
        raise ArgumentError, "hosts: allow must be an Array of Strings" unless allow.is_a?(Array)

        allow.map do |entry|
          raise ArgumentError, "hosts: allow entries must be Strings" unless entry.is_a?(String)
          # "" or "." would become a suffix that matches every host with a dot.
          raise ArgumentError, "hosts: empty allow entry #{entry.inspect}" if entry.delete_prefix(".").empty?

          entry.downcase
        end
      end

      # A suffix such as ".loja.internal" also allows its bare domain "loja.internal".
      def split(entries)
        suffixes, exact = entries.partition { |entry| entry.start_with?(SUFFIX_PREFIX) }
        bare_domains = suffixes.map { |suffix| suffix.delete_prefix(SUFFIX_PREFIX) }
        [Set.new(exact + bare_domains).freeze, suffixes.freeze]
      end

      def allowed?(host)
        return false if host.nil?

        @exact_hosts.include?(host) || @suffixes.any? { |suffix| host.end_with?(suffix) }
      end

      def host_from(env)
        raw = env["HTTP_HOST"]
        return if raw.nil?

        host = raw.downcase
        bracketed = BRACKETED_IPV6.match(host)
        return bracketed[1] if bracketed

        host.sub(PORT_SUFFIX, "")
      end
    end
  end
end
