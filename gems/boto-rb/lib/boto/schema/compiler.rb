# frozen_string_literal: true

module Boto
  class Schema
    # Writes the per-class methods as source. Each field gets its own direct accessor,
    # so a request runs no dynamic dispatch. Generated names are field names, validated by FIELD_NAME.
    class Compiler
      def initialize(schema)
        @schema = schema
        @fields = schema.fields
      end

      def compile
        @schema.class_eval(instance_source, __FILE__, __LINE__)
        @schema.singleton_class.class_eval(class_source, __FILE__, __LINE__)
        self
      end

      private

      def instance_source
        <<~RUBY
          def initialize(#{value_names.join(", ")})
            #{assignments}
            freeze
          end

          def to_h
            #{hash_literal { |field, _index| "__boto_plain(@#{field.name})" }}
          end
        RUBY
      end

      def class_source
        <<~RUBY
          def coerce(input)
            __boto_require_object(input)
            errors = nil
            #{coerce_blocks}
            raise ::Boto::Types::Invalid.new(errors) if errors

            new(#{value_names.join(", ")})
          end

          def serialize(object)
            object.is_a?(Hash) ? __boto_serialize_hash(object) : __boto_serialize_object(object)
          end

          #{serializer_methods}
        RUBY
      end

      # Parameters are positional (v0, v1...) so a field named like a Ruby keyword cannot break the source.
      def value_names
        @fields.each_index.map { |index| value_name(index) }
      end

      def value_name(index)
        "v#{index}"
      end

      def assignments
        @fields.each_with_index.map { |field, index| "@#{field.name} = #{value_name(index)}" }.join("\n")
      end

      def coerce_blocks
        @fields.each_index.map { |index| coerce_block(index) }.join
      end

      def coerce_block(index)
        <<~RUBY
          begin
            #{value_name(index)} = __boto_coerce_field(@fields[#{index}], input)
          rescue ::Boto::Types::Invalid => e
            errors = __boto_add_errors(errors, @fields[#{index}], e)
          end
        RUBY
      end

      def serializer_methods
        <<~RUBY
          def __boto_serialize_object(object)
            #{hash_literal { |field, index| "__boto_dump(@fields[#{index}], object.#{field.name})" }}
          end

          def __boto_serialize_hash(hash)
            #{hash_literal { |field, index| "__boto_dump(@fields[#{index}], __boto_read_output(hash, @fields[#{index}]))" }}
          end

          private :__boto_serialize_object, :__boto_serialize_hash
        RUBY
      end

      def hash_literal(&entry)
        "{ #{pairs(&entry)} }"
      end

      def pairs
        @fields.each_with_index.map { |field, index| "#{field.name}: #{yield(field, index)}" }.join(", ")
      end
    end
  end
end
