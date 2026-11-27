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
          (?<skip>'[^']*'|"[^"]*"|\#(?:\w+[?!=]?|\[\]=?|[<>=!~+\-*\/%&|^]+))
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
          named = 0
          type.scan(SPELLING) do
            match = Regexp.last_match or next
            named += 1 if match[:opener] && COLLECTION_NAMES.value?(match[:name])
          end
          if style == :long
            named < collection_count(types_explainer)
          else
            type != restyle(type)
          end
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
