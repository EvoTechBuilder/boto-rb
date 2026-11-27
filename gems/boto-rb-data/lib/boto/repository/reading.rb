# frozen_string_literal: true

module Boto
  class Repository
    # Read methods, extended into every repository. Filter keys and order fields are checked against the entity
    # before they reach Sequel, so a value from a request can never pick a column the entity does not declare.
    module Reading
      DEFAULT_ORDER = :id

      def find(id)
        first_row(where_dataset(id: id))
      end

      def find!(id)
        find(id) || raise(NotFound.new(mapper.entity, id))
      end

      def all(order: nil, limit: nil, offset: nil)
        select_rows(dataset, order: order, limit: limit, offset: offset)
      end

      # order, limit and offset are reserved: a field with one of these names is filtered with find_by_<field>
      # or query, because the keyword configures the query instead.
      def where(order: nil, limit: nil, offset: nil, **filters)
        select_rows(where_dataset(filters), order: order, limit: limit, offset: offset)
      end

      # Goes through select_rows, not #where, so a field named order still filters.
      def find_by(member, value)
        select_rows(where_dataset({ member => value }), limit: 1).first
      end

      def exists?(**filters)
        !where_dataset(filters).empty?
      end

      def count(**filters)
        where_dataset(filters).count
      end

      private

      # Escape hatch for queries the basics do not cover: the block gets the table dataset and returns one.
      def query
        map_rows(yield(dataset))
      end

      def where_dataset(filters)
        return dataset if filters.empty?

        dataset.where(filters.to_h { |key, value| [mapper.member(key), value] })
      end

      def select_rows(source, order: nil, limit: nil, offset: nil)
        rows = source.order(*order_fields(order))
        rows = rows.limit(non_negative(limit, :limit)) if limit
        rows = rows.offset(non_negative(offset, :offset)) if offset
        map_rows(rows)
      end

      def order_fields(order)
        fields = Array(order)
        fields = [DEFAULT_ORDER] if fields.empty?
        fields.map { mapper.member(_1) }
      end

      def non_negative(value, option)
        return value if value.is_a?(Integer) && value >= 0

        raise ArgumentError, "#{option} must be a non-negative Integer"
      end

      def first_row(source)
        row = source.first
        row && mapper.build(row)
      end

      def map_rows(source)
        source.map { mapper.build(_1) }
      end
    end
  end
end
