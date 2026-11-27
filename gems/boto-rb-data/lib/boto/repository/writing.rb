# frozen_string_literal: true

module Boto
  class Repository
    # Write methods, extended into every repository. Fields are checked against the entity, and id and the
    # timestamps are managed here, so a caller can never set them.
    module Writing
      MANAGED_FIELDS = %i[id created_at updated_at].freeze

      def create(**attrs)
        row = writable_values(attrs).merge(timestamps_for(:created_at, :updated_at))
        id = translate_violations { dataset.insert(row) }
        find!(id)
      end

      # Returns the entity after the write, so a missing id shows up as nil with no extra query.
      def update(id, **attrs)
        values = writable_values(attrs)
        return find(id) if values.empty?

        translate_violations { where_dataset(id: id).update(values.merge(timestamps_for(:updated_at))) }
        find(id)
      end

      def delete(id)
        translate_violations { where_dataset(id: id).delete }.positive?
      end

      # Repository calls inside the block share its connection, which Sequel keeps per fiber or thread.
      def transaction(&)
        database.transaction(&)
      end

      private

      def writable_values(attrs)
        attrs.to_h { |key, value| [writable_member(key), value] }
      end

      def writable_member(key)
        member = mapper.member(key)
        return member unless MANAGED_FIELDS.include?(member)

        raise ArgumentError, %(field "#{member}" is managed by the repository)
      end

      # Only the timestamps the entity declares, so the repository never writes a column the entity lacks.
      def timestamps_for(*fields)
        now = clock.call
        fields.select { mapper.members.include?(_1) }.to_h { [_1, now] }
      end

      # The driver message can carry the offending value, so the error names only the entity.
      def translate_violations
        yield
      rescue Sequel::UniqueConstraintViolation
        raise UniqueViolation, "#{mapper.entity}: unique constraint violated"
      rescue Sequel::ForeignKeyConstraintViolation
        raise ForeignKeyViolation, "#{mapper.entity}: foreign key constraint violated"
      end
    end
  end
end
