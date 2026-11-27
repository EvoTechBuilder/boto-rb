# frozen_string_literal: true

module Boto
  module CLI
    # Turns the arguments of `boto generate` into the blueprint of its kind, after checking them against the project.
    class BlueprintBuilder
      ENDPOINT_KIND = "endpoint"
      REPOSITORY_KIND = "repository"
      MIGRATION_KIND = "migration"
      KINDS = [*Blueprint::KINDS.keys, REPOSITORY_KIND, MIGRATION_KIND].freeze
      ENDPOINT_USAGE = "Usage: boto generate endpoint <project> <name> <verb> <path> [param:type ...] " \
                       "[--body NAME] [--returns NAME]"
      LIBRARY_TEMPLATE = :library
      NO_FIELD_KINDS = ["operation", REPOSITORY_KIND, MIGRATION_KIND].freeze
      TYPE_HINT = "use string, integer, float, boolean, date, time, [type] or the name of a schema in schemas/"

      def initialize(project:, folder:, clock: Time)
        @project = project
        @folder = folder
        @clock = clock
      end

      def build(kind, name, args, options)
        return endpoint(name, args, options) if kind == ENDPOINT_KIND

        ensure_no_endpoint_options!(options)
        ensure_no_table_option!(kind, options)
        ensure_no_fields!(kind, args)
        return repository(name, options) if kind == REPOSITORY_KIND
        return MigrationBlueprint.new(name: name, clock: @clock) if kind == MIGRATION_KIND

        Blueprint.new(kind, name: name, fields: fields(args), namespace: namespace)
      end

      private

      def namespace = @project.namespace_name

      def ensure_no_endpoint_options!(options)
        return unless options[:body] || options[:returns]

        raise Error, "--body and --returns only apply to endpoint"
      end

      def ensure_no_table_option!(kind, options)
        return if kind == REPOSITORY_KIND || options[:table].nil?

        raise Error, "--table only applies to repository"
      end

      def repository(name, options)
        RepositoryBlueprint.new(name: name, namespace: namespace, table: options[:table])
      end

      def ensure_no_fields!(kind, args)
        return unless NO_FIELD_KINDS.include?(kind) && args.any?

        raise Error, "#{kind} takes no fields"
      end

      def endpoint(name, args, options)
        verb, path, *specs = args
        raise Error, ENDPOINT_USAGE if verb.nil? || path.nil?

        ensure_http!
        ensure_schema_option!("body", options[:body])
        ensure_schema_option!("returns", options[:returns])
        EndpointBlueprint.new(name: name, namespace: namespace, route: EndpointRoute.parse(verb, path),
                              fields: fields(specs), body: options[:body], returns: options[:returns],
                              auth: @folder.auth_enabled?)
      end

      def fields(specs)
        specs.map do |spec|
          field = FieldSpec.parse(spec, namespace: namespace)
          ensure_schema!(field)
          field
        end
      end

      # A typo such as price:decimal would otherwise become a missing constant that only fails at boot.
      def ensure_schema!(field)
        reference = field.schema_reference
        return if reference.nil? || @folder.schema?(reference)

        type = reference.delete_suffix("_#{FieldSpec::SCHEMA_SUFFIX}")
        raise Error, %(unknown type "#{type}" for field "#{field.name}" (#{TYPE_HINT}))
      end

      # Same reason as ensure_schema!. A list such as [product] checks product.
      def ensure_schema_option!(option, value)
        return if value.nil?

        schema = FieldSpec::LIST.match(value)&.[](1) || value
        suffixed = ConstantName.new(schema, namespace: namespace).with_suffix(FieldSpec::SCHEMA_SUFFIX)
        reference = suffixed.relative_path
        return if @folder.schema?(reference)

        raise Error, %(unknown schema "#{schema}" for --#{option} (no schemas/#{reference}.rb in #{@project.name}))
      end

      def ensure_http!
        return unless @project.template == LIBRARY_TEMPLATE

        raise Error, "endpoints are only generated for HTTP projects (#{@project.name} is a library)"
      end
    end
  end
end
