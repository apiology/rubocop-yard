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

        # A quoted literal or duck type, which is never edited.
        LITERAL = /'[^']*'|"[^"]*"|\#(?:\w+[?!=]?|\[\]=?|[<>=!~+\-*\/%&|^]+)/

        # Splits a type into the parts whose spelling matters: a quoted literal
        # or duck type, which is left alone; a name with the collection opener
        # that follows it, if any; or an opener with no name.
        SPELLING = /
          (?<skip>#{LITERAL})
          |(?<name>[\w:]+)(?<space>\s*)(?<opener>[<({])?
          |(?<bare>[<({])
        /x

        # Brackets, commas and names, for finding where a `Hash<` ends.
        STRUCTURE = /(?<skip>#{LITERAL}|=>)|(?<name>[\w:]+)|(?<open>[<({\[])|(?<close>[>)}\]])|(?<comma>,)/

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
          each_types_explainer(docstring) do |type, types_explainer|
            next unless wrong_style?(type, types_explainer)

            add_offense(comment, message: "`#{type}` is using #{bad_style} style syntax") do |corrector|
              corrector.replace(comment, comment.source.sub(/\[(.*)\]/) { "[#{restyle(type)}]" })
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
          case types_explainer
          when ::YARD::Tags::TypesExplainer::HashCollectionType
            children = types_explainer.key_value_pairs.flatten
          when ::YARD::Tags::TypesExplainer::CollectionType
            children = types_explainer.types
          else
            children = group_members(types_explainer)
            return children.inject(0) { |total, child| total + collection_count(child) }
          end
          own = COLLECTION_NAMES.value?(types_explainer.name) ? 1 : 0
          children.inject(own) { |total, child| total + collection_count(child) }
        end

        # GroupType and IntersectionType need yard 0.9.46 or later.
        def group_members(types_explainer)
          if defined?(::YARD::Tags::TypesExplainer::GroupType) &&
             types_explainer.is_a?(::YARD::Tags::TypesExplainer::GroupType)
            types_explainer.types
          elsif defined?(::YARD::Tags::TypesExplainer::IntersectionType) &&
                types_explainer.is_a?(::YARD::Tags::TypesExplainer::IntersectionType)
            types_explainer.types
          else
            []
          end
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
          tokens = []
          type.scan(STRUCTURE) do
            match = Regexp.last_match or next
            kind = %i[name open close comma].find { match[_1] } or next
            tokens << [kind, match.begin(0), match.end(0)]
          end

          tokens.each_index.reverse_each do |index|
            kind, start, name_end = tokens.fetch(index)
            next unless kind == :name && type[start...name_end] == 'Hash'

            slots = hash_angle_slots(type, tokens, index + 1, name_end) or next
            open_end, comma, close = slots
            key = type[open_end...comma.first].to_s.strip
            value = type[comma.last...close].to_s.strip
            rewritten = "#{type[0...start]}Hash{#{key} => #{value}}#{type[(close + 1)..]}"
            return rewritten if parses?(rewritten)
          end
          nil
        end

        # @return [Array(Integer, Array(Integer, Integer), Integer), nil] where
        #   the slots start, the one comma between them, and the closing `>`
        def hash_angle_slots(type, tokens, index, name_end)
          kind, start, open_end = tokens[index]
          return unless kind == :open && type[start] == '<' && type[name_end...start].to_s.strip.empty?

          depth = 0
          commas = []
          tokens.drop(index).each do |token_kind, token_start, token_end|
            depth += 1 if token_kind == :open
            depth -= 1 if token_kind == :close
            commas << [token_start, token_end] if token_kind == :comma && depth == 1
            next unless depth.zero?

            comma = commas.first
            return commas.size == 1 && comma ? [open_end, comma, token_start] : nil
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
