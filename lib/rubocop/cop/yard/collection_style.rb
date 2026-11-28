# frozen_string_literal: true

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

        IMPLIED_NAME = { '<' => 'Array', '(' => 'Array', '{' => 'Hash' }.freeze

        SPELLING = /
          (?<skip>#{LITERAL_OR_DUCK_TYPE})
          |(?<name>[\w:]+)(?<space>\s*)(?<opener>[<({])?
          |(?<bare>[<({])
        /x

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
          each_types_explainer(docstring) do |type, types_explainer, index|
            next unless wrong_style?(type, types_explainer)

            add_offense(comment, message: "`#{type}` is using #{bad_style} style syntax") do |corrector|
              replace_tag_type(corrector, comment, index, type, restyle(type))
            end
          end
        end

        # yard names `<T>` and `Array<T>` alike, so only the source shows which is written.
        def wrong_style?(type, types_explainer)
          return type != restyle(type) if style == :short

          named_collection_count(type) < collection_count(types_explainer)
        end

        def named_collection_count(type)
          count = 0
          type.scan(SPELLING) do
            match = Regexp.last_match or next
            count += 1 if match[:opener] && IMPLIED_NAME.value?(match[:name])
          end
          count
        end

        def collection_count(types_explainer)
          collection_nodes(types_explainer).count { IMPLIED_NAME.value?(_1.name) }
        end

        def restyle(type)
          type = hash_braces(type) if style == :short
          type.gsub(SPELLING) do |text|
            match = Regexp.last_match or next text
            bare = match[:bare]
            name = match[:name]
            opener = match[:opener]
            if bare
              style == :long ? "#{IMPLIED_NAME.fetch(bare)}#{bare}" : text
            elsif name && opener && style == :short && IMPLIED_NAME[opener] == name
              "#{match[:space]}#{opener}"
            else
              text
            end
          end
        end

        # yard 0.9.46 reads `Hash<K, V>` as a Hash, whose only short form is `{K => V}`.
        def hash_braces(type)
          loop do
            rewritten = rewrite_innermost_hash_angle(type)
            return type if rewritten.nil?

            type = rewritten
          end
        end

        def rewrite_innermost_hash_angle(type)
          tokens = type_tokens(type)
          tokens.each_index.reverse_each do |index|
            kind, start, name_end = tokens.fetch(index)
            next unless kind == :name && type[start...name_end] == 'Hash'

            open_kind, open_start, = tokens[index + 1]
            angle_follows = open_kind == :open && open_start && type[open_start] == '<' &&
                            type[name_end...open_start].to_s.strip.empty?
            next unless angle_follows

            rewritten = key_value_braces(type, tokens, index + 1, start, 'Hash')
            return rewritten if rewritten && parses?(rewritten)
          end
          nil
        end

        def parses?(type)
          parse_type(type)
          true
        rescue SyntaxError
          false
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
