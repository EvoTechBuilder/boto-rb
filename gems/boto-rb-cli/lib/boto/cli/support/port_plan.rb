# frozen_string_literal: true

require "set"

module Boto
  module CLI
    # Decides the port of each project a run serves. Pure: the caller reads the PORT values and supplies free_port.
    class PortPlan
      # declared_port: the raw PORT of the project's own .env files, or nil. gateway: the project mounts its refs.
      Entry = Data.define(:name, :refs, :gateway, :declared_port)
      # ports: name => Integer. random: names whose port came from free_port. gateways: gateway name => its refs.
      Result = Data.define(:ports, :random, :gateways)

      PORT_PATTERN = /\A\d+\z/
      PORT_RANGE = (0..65_535)
      RANDOM = :random
      SEQUENTIAL = :sequential
      INVALID_MESSAGE = %(%<name>s: invalid PORT "%<value>s")
      CONFLICT_MESSAGE = "%<names>s both use PORT %<port>d"

      # entries: in topological order. free_port: called with the host, returns a port the OS found free.
      def initialize(entries:, base_port:, host:, free_port:)
        @entries = entries
        @base_port = base_port
        @host = host
        @free_port = free_port
        @services = entries.select(&:gateway).flat_map(&:refs).to_set
      end

      def call
        requests = entries.to_h { |entry| [entry.name, request_for(entry)] }
        check_conflicts(requests)
        ports = requests.select { |_name, request| request.is_a?(Integer) }
        assign_sequential(requests, ports)
        assign_random(requests, ports)
        build_result(requests, ports)
      end

      private

      attr_reader :entries, :base_port, :host, :free_port, :services

      def request_for(entry)
        declared = declared_port(entry)
        return declared if declared&.positive?
        return RANDOM if declared&.zero? || services.include?(entry.name)
        return base_port if entry.gateway

        SEQUENTIAL
      end

      def declared_port(entry)
        value = entry.declared_port
        return if value.nil?

        port = value.to_i if PORT_PATTERN.match?(value)
        return port if port && PORT_RANGE.cover?(port)

        raise Error, format(INVALID_MESSAGE, name: entry.name, value: value)
      end

      def check_conflicts(requests)
        fixed = requests.select { |_name, request| request.is_a?(Integer) }
        port, users = fixed.group_by { |_name, request| request }.find { |_port, group| group.size > 1 }
        return unless port

        raise Error, format(CONFLICT_MESSAGE, names: users.map(&:first).join(" and "), port: port)
      end

      # Sequential projects take the lowest port from base_port that no fixed project holds.
      def assign_sequential(requests, ports)
        candidate = base_port
        requests.each do |name, request|
          next unless request == SEQUENTIAL

          candidate += 1 while ports.value?(candidate)
          ports[name] = candidate
          candidate += 1
        end
      end

      def assign_random(requests, ports)
        requests.each { |name, request| ports[name] = unused_free_port(ports) if request == RANDOM }
      end

      # The ports are only picked here and bound later, so the OS may hand out the same free port twice.
      def unused_free_port(ports)
        port = free_port.call(host)
        port = free_port.call(host) while ports.value?(port)
        port
      end

      def build_result(requests, ports)
        Result.new(
          ports: entries.to_h { |entry| [entry.name, ports.fetch(entry.name)] },
          random: requests.filter_map { |name, request| name if request == RANDOM },
          gateways: entries.select(&:gateway).to_h { |entry| [entry.name, entry.refs] }
        )
      end
    end
  end
end
