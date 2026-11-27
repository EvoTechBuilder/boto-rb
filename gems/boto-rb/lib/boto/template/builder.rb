# frozen_string_literal: true

module Boto
  class Template
    # The `t` of Template.define: keeps the options and validates them, naming the file that declared them.
    class Builder
      FOLDERS = %w[apps libs workers].freeze
      BOOLEANS = [true, false].freeze

      def initialize(name:, path:, source:, official:)
        @name = name
        @path = path
        @source = source
        @official = official
        @options = { folder: nil, http: false, files: nil, summary: nil, legacy_services: false }
      end

      def folder(value) = store(:folder, value)
      def http(value) = store(:http, value)
      def files(value) = store(:files, value)
      def summary(value) = store(:summary, value)

      # Internal to boto-rb: only official declarations may set it (the old services/ layout).
      def legacy_services(value) = store(:legacy_services, value)

      def to_template
        validate!
        Template.new(name: @name.to_sym, source: @source, **@options)
      end

      # Unknown options fail at boot, with the declaring file, instead of as a bare NoMethodError.
      def method_missing(option, *)
        invalid!("unknown option #{option}")
      end

      def respond_to_missing?(*) = false

      private

      def store(option, value)
        @options[option] = value
        nil
      end

      def validate!
        check_name
        check_folder
        check_booleans
        check_files
        check_summary
      end

      def check_name
        invalid!("name must be a Symbol or String, got #{@name.inspect}") unless @name.is_a?(Symbol) || @name.is_a?(String)
        invalid!("name #{@name.inspect} must match #{Template::NAME_FORMAT.source}") unless Template::NAME_FORMAT.match?(@name.to_s)
      end

      def check_folder
        invalid!("folder is required") if option(:folder).nil?
        invalid!("folder must be one of #{FOLDERS.join(", ")}, got #{option(:folder).inspect}") unless FOLDERS.include?(option(:folder))
      end

      def check_booleans
        %i[http legacy_services].each { |key| check_boolean(key) }
        invalid!("legacy_services is internal to boto-rb") if option(:legacy_services) && !@official
      end

      def check_boolean(key)
        invalid!("#{key} must be true or false, got #{option(key).inspect}") unless BOOLEANS.include?(option(key))
      end

      def check_files
        value = option(:files)
        return if value.nil? || (value.is_a?(String) && File.directory?(value))

        invalid!("files must be an existing directory, got #{value.inspect}")
      end

      def check_summary
        value = option(:summary)
        invalid!("summary must be a String, got #{value.inspect}") unless value.nil? || value.is_a?(String)
      end

      def option(key) = @options.fetch(key)

      def invalid!(reason)
        raise ::Boto::Templates::InvalidTemplateError, "#{@path}: #{reason}"
      end
    end
  end
end
