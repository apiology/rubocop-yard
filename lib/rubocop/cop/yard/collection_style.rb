# frozen_string_literal: true

require 'strscan'

module RuboCop
  module Cop
    module YARD
      # @example EnforcedStyle short
      #
      #   # bad
      #   # @param [Hash{KeyType => ValueType}]
      #
      #   # bad
      #   # @param [Array(String)]
      #
      #   # bad
      #   # @param [Array<String>]
      #
      #   # good
      #   # @param [{KeyType => ValueType}]
      #
      #   # good
      #   # @param [(String)]
      #
      #   # good
      #   # @param [<String>]
      #
      # @example EnforcedStyle long (default)
      #   # bad
      #   # @param [{KeyType => ValueType}]
      #
      #   # bad
      #   # @param [(String)]
      #
      #   # bad
      #   # @param [<String>]
      #
      #   # good
      #   # @param [Hash{KeyType => ValueType}]
      #
      #   # good
      #   # @param [Array(String)]
      #
      #   # good
      #   # @param [Array<String>]
      class CollectionStyle < Base
        include YARD::Helper
        include RangeHelp
        include ConfigurableEnforcedStyle
        extend AutoCorrector

        # The name the long style writes before each collection's opening token.
        COLLECTION_NAMES = {
          collection_start: 'Array',
          fixed_collection_start: 'Array',
          hash_collection_start: 'Hash'
        }.freeze

        def on_new_investigation
          processed_source.comments.each do |comment|
            next if inline_comment?(comment)
            next unless include_yard_tag?(comment)

            check(comment)
          end
        end

        private

        def check(comment)
          docstring = ::YARD::DocstringParser.new.parse(comment.text.gsub(/\A#\s*/, ''))
          each_types_explainer(docstring) do |type, _types_explainer|
            correct_type = restyle(type)
            unless correct_type.nil? || type == correct_type
              add_offense(comment, message: "`#{type}` is using #{bad_style} style syntax") do |corrector|
                corrector.replace(comment, comment.source.sub(/\[(.*)\]/) { "[#{correct_type}]" })
              end
            end
          end
        end

        # Adds or removes each collection's name to match the style, leaving
        # the rest as written: long style turns `(<A> | B)` into
        # `Array(Array<A> | B)`. Returns nil if yard can't tokenize the type.
        def restyle(type)
          scanner = StringScanner.new(type)
          out = []
          name_index = nil
          until scanner.eos?
            kind, = ::YARD::Tags::TypesExplainer::Parser::TOKENS.find { |_, regexp| regexp && scanner.scan(regexp) }
            return if kind.nil?

            name = COLLECTION_NAMES[kind]
            if name && name_index.nil?
              out << name if style == :long
            elsif name && out[name_index] == name && style == :short
              out[name_index] = ''
            end

            if kind == :type_name
              name_index = out.size
            elsif kind != :whitespace
              name_index = nil
            end
            out << scanner.matched
          end
          out.join
        end

        def bad_style
          if style == :long
            :short
          else
            :long
          end
        end

        def include_yard_tag?(comment)
          comment.source.match?(/@(?:param|return|option|raise|yieldparam|yieldreturn)\s+.*\[.*\]/)
        end
      end
    end
  end
end
