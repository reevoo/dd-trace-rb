module Datadog
  module Contrib
    module Elasticsearch
      # Quantize contains ES-specific resource quantization tools.
      module Quantize
        PLACEHOLDER = '?'.freeze
        EXCLUDE_KEYS = [].freeze
        KEEP_KEYS = [:_index, :_type, :_id].freeze
        DEFAULT_OPTIONS = { exclude: EXCLUDE_KEYS, keep: KEEP_KEYS }.freeze

        ID_REGEXP = %r{\/([0-9]+)([\/\?]|$)}
        ID_PLACEHOLDER = '/?\2'.freeze

        INDEX_REGEXP = /[0-9]{2,}/
        INDEX_PLACEHOLDER = '?'.freeze

        module_function

        # Very basic quantization, complex processing should be done in the agent
        def format_url(url)
          quantized_url = url.gsub(ID_REGEXP, ID_PLACEHOLDER)
          quantized_url.gsub(INDEX_REGEXP, INDEX_PLACEHOLDER)
        end

        def format_body(body, options = {})
          # Determine if bulk query or not, based on content
          statements = body.end_with?("\n") ? body.split("\n") : [body]

          # Parse each statement and quantize them.
          statements.collect do |string|
            reserialize_json(string) do |obj|
              format_statement(obj, options)
            end
          end.join("\n")
        end

        def format_statement(statement, options = {})
          combined_options = merge_options(DEFAULT_OPTIONS, options)

          case statement
          when Hash
            statement.each_with_object({}) do |(key, value), quantized|
              if combined_options[:keep].include?(key.to_sym)
                quantized[key] = value
              elsif !combined_options[:exclude].include?(key.to_sym)
                quantized[key] = format_value(value, options)
              end
            end
          else
            format_value(statement, options)
          end
        end

        def format_value(value, options = {})
          case value
          when Hash
            format_statement(value, options)
          when Array
            format_value(value.first, options)
          else
            PLACEHOLDER
          end
        end

        def merge_options(original, additional)
          {}.tap do |options|
            options[:keep] = (original[:keep] || []).dup.concat(additional[:keep] || []).uniq
            options[:exclude] = (original[:exclude] || []).dup.concat(additional[:exclude] || []).uniq
          end
        end

        # Parses a JSON object from a string, passes its value
        # to the block provided, and dumps its result back to JSON.
        # If JSON parsing fails, it prints fail_value.
        def reserialize_json(string, fail_value = PLACEHOLDER)
          return string unless block_given?
          begin
            JSON.dump(yield(JSON.parse(string)))
          rescue JSON::ParserError
            # If it can't parse/dump, don't raise an error.
            fail_value
          end
        end
      end
    end
  end
end
