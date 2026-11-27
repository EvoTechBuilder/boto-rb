# frozen_string_literal: true

module Boto
  module CLI
    # Maps a project name such as "products/show" to the constant it defines under the project namespace.
    class ConstantName
      # Rejects "..", leading or trailing "/", empty segments, uppercase and spaces before any path or constant is built.
      PATTERN = %r{\A[a-z][a-z0-9_]*(/[a-z][a-z0-9_]*)*\z}

      def initialize(name, namespace:)
        raise Error, %(invalid name "#{name}" (use lowercase snake_case, folders with /)) unless PATTERN.match?(name)

        @name = name
        @namespace = namespace
      end

      def segments = @name.split("/")

      def relative_path = @name

      def class_name = camelize(segments.last)

      def modules = [@namespace, *segments[0...-1].map { |segment| camelize(segment) }]

      def constant = [*modules, class_name].join("::")

      def with_suffix(suffix)
        last = segments.last
        return self if last == suffix || last.end_with?("_#{suffix}")

        self.class.new([*segments[0...-1], "#{last}_#{suffix}"].join("/"), namespace: @namespace)
      end

      private

      def camelize(segment) = segment.split("_").map(&:capitalize).join
    end
  end
end
