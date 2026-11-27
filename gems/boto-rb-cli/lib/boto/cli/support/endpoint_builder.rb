# frozen_string_literal: true

module Boto
  module CLI
    # Works out verb, route and schemas of an endpoint, given explicitly or derived from the action in its name.
    class EndpointBuilder
      USAGE = "Usage: boto generate endpoint <project> <name> [<verb> <path>] [param:type ...] " \
              "[--body NAME] [--returns NAME] [--no-body] [--no-returns]"

      # fields: a callable that parses the param:type specs into fields, checking them against the project.
      def initialize(project:, folder:, fields:)
        @project = project
        @folder = folder
        @fields = fields
        @notices = []
      end

      def build(name, args, options)
        return explicit(name, args, options) if explicit?(args)

        by_convention(name, args, options)
      end

      private

      def namespace = @project.namespace_name

      # The explicit form starts with the verb; a param:type spec always has a colon, a verb or a path never does.
      def explicit?(args) = args.any? && !args.first.include?(":")

      def explicit(name, args, options)
        verb, path, *specs = args
        raise Error, USAGE if path.nil?

        build_endpoint(name, EndpointRoute.parse(verb, path), specs,
                       body: checked_schema("body", options[:body]),
                       returns: checked_schema("returns", options[:returns]))
      end

      def by_convention(name, args, options)
        rule = EndpointConvention.for(name) || raise(Error, unknown_action(name))
        build_endpoint(name, EndpointRoute.parse(rule.verb, rule.path), args,
                       body: deduced_schema("body", rule.body, options[:body], options[:no_body]),
                       returns: deduced_schema("returns", rule.returns, options[:returns], options[:no_returns]))
      end

      def build_endpoint(name, route, specs, body:, returns:)
        EndpointBlueprint.new(name: name, namespace: namespace, route: route, fields: @fields.call(specs),
                              body: body, returns: returns, auth: @folder.auth_enabled?, notices: @notices)
      end

      # An explicit --body or --returns wins and must exist, as before: a typo is refused, not skipped.
      def checked_schema(option, value)
        return value if value.nil? || schema?(value)

        raise Error, "unknown schema \"#{schema_name(value)}\" for --#{option} " \
                     "(no schemas/#{schema_reference(value)}.rb in #{@project.name})"
      end

      # A deduced schema is kept only if its file exists; otherwise it is left out and the output says so.
      def deduced_schema(option, deduced, given, disabled)
        return checked_schema(option, given) if given
        return if disabled || deduced.nil?
        return deduced if schema?(deduced)

        @notices << %(skip --#{option} #{deduced} (no schemas/#{schema_reference(deduced)}.rb))
        nil
      end

      def schema?(value) = @folder.schema?(schema_reference(value))

      def schema_reference(value)
        ConstantName.new(schema_name(value), namespace: namespace).with_suffix(FieldSpec::SCHEMA_SUFFIX).relative_path
      end

      def schema_name(value) = FieldSpec::LIST.match(value)&.[](1) || value

      def unknown_action(name)
        known = EndpointConvention::KNOWN_ACTIONS.join(", ")
        %(unknown action "#{name.split("/").last}" for #{name}; known actions: #{known}. ) +
          "Otherwise pass the verb and path: boto g endpoint #{@project.name} #{name} post /#{name}"
      end
    end
  end
end
