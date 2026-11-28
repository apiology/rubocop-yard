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

        # Names yard gives a collection written without one: `<T>` and `(T)`
        # are Arrays, `{K => V}` is a Hash.
        COLLECTION_NAMES = { '<' => 'Array', '(' => 'Array', '{' => 'Hash' }.freeze

        # Splits a type into the parts whose spelling matters: a quoted literal
        # or duck type, which is left alone; a name with the collection opener
        # that follows it, if any; or an opener with no name.
        SPELLING = /
          (?<skip>#{LITERAL})
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

        # yard names `<String>` and `Array<String>` both Array, so the parse
        # tree gives how many Array and Hash collections there are, and the
        # source gives how many of them are written with their name.
        def wrong_style?(type, types_explainer)
          return type != restyle(type) if style == :short

          named = 0
          type.scan(SPELLING) do
            match = Regexp.last_match or next
            named += 1 if match[:opener] && COLLECTION_NAMES.value?(match[:name])
          end
          named < collection_count(types_explainer)
        end

        # @return [Integer] the Array and Hash collections in the parse tree
        def collection_count(types_explainer)
          collection_nodes(types_explainer).count { COLLECTION_NAMES.value?(_1.name) }
        end

        # Long style names each unnamed collection; short style drops the name
        # where the bare form means the same (`Array<`, `Array(`, `Hash{`).
        # Everything else stays as written.
        def restyle(type)
          type = hash_braces(type) if style == :short
          type.gsub(SPELLING) do |text|
            match = Regexp.last_match or next text
            bare = match[:bare]
            name = match[:name]
            opener = match[:opener]
            if bare
              style == :long ? "#{COLLECTION_NAMES.fetch(bare)}#{bare}" : text
            elsif name && opener && style == :short && COLLECTION_NAMES[opener] == name
              "#{match[:space]}#{opener}"
            else
              text
            end
          end
        end

        # Rewrites each `Hash<K, V>` as `Hash{K => V}`, keeping K and V as
        # written: yard 0.9.46 reads both as a Hash, and only the braces have a
        # short form. Innermost first, so `Hash<K, Hash<K, V>>` works; a
        # `Hash<...>` without exactly two slots is a plain collection and stays.
        def hash_braces(type)
          loop do
            rewritten = rewrite_last_hash_angle(type)
            return type if rewritten.nil?

            type = rewritten
          end
        end

        # @return [String, nil] nil if no `Hash<K, V>` is left
        def rewrite_last_hash_angle(type)
          tokens = type_tokens(type)
          tokens.each_index.reverse_each do |index|
            kind, start, name_end = tokens.fetch(index)
            next unless kind == :name && type[start...name_end] == 'Hash'

            open_kind, open_start, = tokens[index + 1]
            next unless open_kind == :open && open_start && type[open_start] == '<'
            next unless type[name_end...open_start].to_s.strip.empty?

            rewritten = hash_braces_at(type, tokens, index + 1, start, 'Hash')
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
