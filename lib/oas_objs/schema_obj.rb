require 'oas_objs/helpers'
require 'open_api/config'
require 'oas_objs/ref_obj'
require 'oas_objs/example_obj'
require 'oas_objs/schema_obj_helpers'

module OpenApi
  module DSL
    # https://github.com/OAI/OpenAPI-Specification/blob/OpenAPI.next/versions/3.0.0.md#schemaObject
    class SchemaObj < Hash
      include SchemaObjHelpers
      include Helpers

      attr_accessor :processed, :type, :preprocessed

      def initialize(type, schema_info)
        self.preprocessed = false
        self.processed = { }
        self.type = type
        merge! schema_info
      end

      def process(options = { inside_desc: false })
        processed.merge!(processed_type)
        reducx(additional_properties, enum_and_length, range, format, pattern_default_and_other, desc(options)).then_merge!
      end

      def desc(inside_desc:)
        result = __desc ? auto_generate_desc : _desc
        return unless inside_desc
        { description: result }
      end

      def processed_type(type = self.type)
        t = type.class.in?([Hash, Array, Symbol]) ? type : type.to_s.downcase
        if t.is_a? Hash
          hash_type(t)
        elsif t.is_a? Array
          array_type(t)
        elsif t.is_a? Symbol
          RefObj.new(:schema, t).process
        elsif t.in? %w[ float double int32 int64 ]
          { type: t.match?('int') ? 'integer' : 'number', format: t }
        elsif t.in? %w[ binary base64 uri ]
          { type: 'string', format: t }
        elsif t == 'file' # TODO
          { type: 'string', format: Config.file_format }
        elsif t == 'datetime'
          { type: 'string', format: 'date-time' }
        elsif t.match?(/\{=>.*\}/)
          self[:values_type] = t[3..-2]
          { type: 'object' }
        else # other string
          { type: t }
        end
      end

      def additional_properties
        return { } if processed[:type] != 'object' || _addProp.nil?
        {
            additionalProperties: SchemaObj.new(_addProp, { }).process(inside_desc: true)
        }
      end

      def enum_and_length
        process_enum_info
        process_range_enum_and_lth

        # generate length range fields by _lth array
        if (lth = _length || '').is_a?(Array)
          min, max = [lth.first&.to_i, lth.last&.to_i]
        elsif lth['ge']
          min = lth.to_s.split('_').last.to_i
        elsif lth['le']
          max = lth.to_s.split('_').last.to_i
        end

        if processed[:type] == 'array'
          { minItems: min, maxItems: max }
        else
          { minLength: min, maxLength: max }
        end.merge!(enum: _enum).keep_if &value_present
      end

      def range
        range = _range || { }
        {
                     minimum: range[:gt] || range[:ge],
            exclusiveMinimum: range[:gt].present? ? true : nil,
                     maximum: range[:lt] || range[:le],
            exclusiveMaximum: range[:lt].present? ? true : nil
        }.keep_if &value_present
      end

      def format
        result = { is: _is }
        # `format` that generated in process_type() may be overwrote here.
        result[:format] = _format || _is if processed[:format].blank? || _format.present?
        result
      end

      def pattern_default_and_other
        {
            pattern:  _pattern.is_a?(String) ? _pattern : _pattern&.inspect&.delete('/'),
            default:  _default,
            example:  _exp.present? ? ExampleObj.new(_exp).process : nil,
            examples: _exps.present? ? ExampleObj.new(_exps, self[:exp_by], multiple: true).process : nil,
            as: _as, permit: _permit, not_permit: _npermit, req_if: _req_if, opt_if: _opt_if, blankable: _blank
        }
      end


      { # SELF_MAPPING
          _enum:    %i[ enum in  values  allowable_values ],
          _value:   %i[ must_be  value   allowable_value  ],
          _range:   %i[ range    number_range             ],
          _length:  %i[ length   lth     size             ],
          _format:  %i[ format   fmt                      ],
          _pattern: %i[ pattern  regexp  pt   reg         ],
          _default: %i[ default  dft     default_value    ],
          _desc:    %i[ desc     description  d           ],
          __desc:   %i[ desc!    description! d!          ],
          _exp:     %i[ example                           ],
          _exps:    %i[ examples                          ],
          _addProp: %i[ additional_properties add_prop values_type ],
          _is:      %i[ is_a     is                       ], # NOT OAS Spec, see documentation/parameter.md
          _as:      %i[ as   to  for     map  mapping     ], # NOT OAS Spec, it's for zero-params_processor
          _permit:  %i[ permit   pmt                      ], # ditto
          _npermit: %i[ npmt     not_permit   unpermit    ], # ditto
          _req_if:  %i[ req_if   req_when                 ], # ditto
          _opt_if:  %i[ opt_if   opt_when                 ], # ditto
          _blank:   %i[ blank    blankable                ], # ditto
      }.each do |key, aliases|
        define_method key do
          return self[key] unless self[key].nil?
          aliases.each { |alias_name| self[key] = self[alias_name] if self[key].nil? }
          self[key]
        end
        define_method("#{key}=") { |value| self[key] = value }
      end
    end
  end
end


__END__

Schema Object Examples

Primitive Sample

{
  "type": "string",
  "format": "email",
  "examples": {
    "exp1": {
      "value": 'val'
    }
  }
}

Simple Model

{
  "type": "object",
  "required": [
    "name"
  ],
  "properties": {
    "name": {
      "type": "string"
    },
    "address": {
      "$ref": "#/components/schemas/Address"
    },
    "age": {
      "type": "integer",
      "format": "int32",
      "minimum": 0
    }
  }
}