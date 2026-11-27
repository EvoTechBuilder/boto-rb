# frozen_string_literal: true

module Boto
  module CLI
    # Derives verb, route and schemas from an endpoint name, e.g. "admin/products/show".
    class EndpointConvention
      Rule = Data.define(:verb, :path, :body, :returns)

      # action => [verb, path suffix, body, returns]; %s is the singular resource.
      ACTIONS = {
        "index" => ["get", "", nil, "[%s]"],
        "show" => ["get", "/:id", nil, "%s"],
        "create" => ["post", "", "%s_input", "%s"],
        "update" => ["patch", "/:id", "%s_input", "%s"],
        "destroy" => ["delete", "/:id", nil, nil],
        "search" => ["query", "/search", "%s_filter", "[%s]"]
      }.freeze
      KNOWN_ACTIONS = ACTIONS.keys.freeze

      def self.for(name)
        *folders, action = name.split("/")
        return if folders.empty? || folders.include?("") || !ACTIONS.key?(action)

        verb, suffix, body, returns = ACTIONS.fetch(action)
        resource = singular(folders.last)
        Rule.new(verb: verb, path: "/#{folders.join("/")}#{suffix}",
                 body: body && format(body, resource), returns: returns && format(returns, resource))
      end

      # Only used to locate the schema file; an irregular plural simply won't find one.
      def self.singular(word)
        case word
        when /ies\z/ then word.delete_suffix("ies") + "y"
        when /ss\z/ then word
        when /s\z/ then word.delete_suffix("s")
        else word
        end
      end
    end
  end
end
