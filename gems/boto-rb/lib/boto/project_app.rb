# frozen_string_literal: true

module Boto
  # Gives endpoints and operations `app`: the ProjectContext of the project their class belongs to.
  module ProjectApp
    NAMESPACE_SEPARATOR = "::"
    NOT_BOOTED_MESSAGE = "%s is not in a booted project"

    class NotBootedError < StandardError; end

    # Extended onto a project namespace (Catalogo) at boot. Its app is replaced on every boot.
    module Namespace
      attr_reader :app

      def bind_app(context) = @app = context
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    def app = self.class.project_app

    module ClassMethods
      def project_app
        namespace = project_namespace
        return namespace.app if namespace.is_a?(Namespace) && namespace.app

        raise NotBootedError, format(NOT_BOOTED_MESSAGE, self)
      end

      private

      # The namespace is the first segment of the class name and is looked up once per class.
      def project_namespace
        @project_namespace ||= find_namespace
      end

      def find_namespace
        root = name.to_s.split(NAMESPACE_SEPARATOR).first
        Object.const_get(root, false) if root && Object.const_defined?(root, false)
      end
    end
  end
end
