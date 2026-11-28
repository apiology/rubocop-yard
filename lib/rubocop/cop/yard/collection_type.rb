# frozen_string_literal: true

module RuboCop
  module Cop
    module YARD
      # @example common
      #   # bad
      #   # @param [Hash<Symbol, String>]
      #
      #   # bad
      #   # @param [Hash(String)]
      #
      #   # bad
      #   # @param [Array{Symbol => String}]
      #
      #   # good
      #   # @param [Hash{Symbol => String}]
      #
      #   # good
      #   # @param [Array(String)]
      #
      #   # good
      #   # @param [Hash{Symbol => String}]
      class CollectionType < Base
        include YARD::Helper
        include RangeHelp
        include ConfigurableEnforcedStyle
        extend AutoCorrector

        # The type as written, its index in the tag, and its collections in
        # source order, for correcting just one of them.
        class Target
          attr_reader :type, :index, :nodes

          def initialize(type, index, nodes)
            @type = type
            @index = index
            @nodes = nodes
          end
        end

        def on_new_investigation
          processed_source.comments.each do |comment|
            next if inline_comment?(comment)
            next unless include_yard_tag?(comment)

            docstring = ::YARD::DocstringParser.new.parse(comment.text.gsub(/\A#\s*/, ''))
            check_mismatch_collection_type(comment, docstring)
          end
        end

        private

        def check_mismatch_collection_type(comment, docstring)
          each_types_explainer(docstring) do |type, types_explainer, index|
            target = Target.new(type, index, collection_nodes(types_explainer))
            check_mismatch_collection_type_one(comment, types_explainer, target)
          end
        end

        def check_mismatch_collection_type_one(comment, types_explainer, target)
          case types_explainer
          when ::YARD::Tags::TypesExplainer::HashCollectionType
            case types_explainer.name
            when 'Hash'
              types_explainer.key_types.each { |t| check_mismatch_collection_type_one(comment, t, target) }
              types_explainer.value_types.each { |t| check_mismatch_collection_type_one(comment, t, target) }
            when 'Array'
              message = "`{KeyType => ValueType}` is the Hash collection type syntax."
              add_offense(tag_range_for_comment(comment), message: message) do |corrector|
                correct_collection(corrector, comment, target, types_explainer, 'Hash')
              end
            end
          when ::YARD::Tags::TypesExplainer::FixedCollectionType
            case types_explainer.name
            when 'Hash'
              if types_explainer.types.length == 2
                message = "`Hash(Key, Value)` is miswritten of `Hash<Key, Value>` in perhaps"
                add_offense(tag_range_for_comment(comment), message: message) do |corrector|
                  correct_collection(corrector, comment, target, types_explainer, nil)
                end
              else
                message = "`(Type)` is the fixed collection type syntax."
                add_offense(tag_range_for_comment(comment), message: message) do |corrector|
                  correct_collection(corrector, comment, target, types_explainer, 'Array')
                end
              end
            when 'Array'
              types_explainer.types.each { |t| check_mismatch_collection_type_one(comment, t, target) }
            end
          when ::YARD::Tags::TypesExplainer::CollectionType
            case types_explainer.name
            when 'Hash'
              if types_explainer.types.length == 2
                message = "`Hash<Key, Value>` is ambiguous syntax"
                add_offense(tag_range_for_comment(comment), message: message) do |corrector|
                  correct_collection(corrector, comment, target, types_explainer, nil)
                end
              else
                message = "`<Type>` is the collection type syntax."
                add_offense(tag_range_for_comment(comment), message: message) do |corrector|
                  correct_collection(corrector, comment, target, types_explainer, 'Array')
                end
              end
            when 'Array'
              types_explainer.types.each { |t| check_mismatch_collection_type_one(comment, t, target) }
            end
          else
            group_members(types_explainer).each { |t| check_mismatch_collection_type_one(comment, t, target) }
          end
        end

        # Renames the collection to +name+ (or drops the name in short style),
        # or with a nil +name+ rewrites its two slots as `{K => V}`, editing
        # only that collection in the type as written.
        def correct_collection(corrector, comment, target, node, name)
          type = target.type
          nodes = target.nodes
          tokens = type_tokens(type)
          openers = collection_openers(type, tokens)
          position = nodes.index { _1.equal?(node) }
          return unless position && openers.size == nodes.size

          name_start, opener_index = openers.fetch(position)
          prefix = style == :long ? (name || 'Hash') : ''
          if name
            open_start = tokens.fetch(opener_index)[1]
            corrected = "#{type[0...name_start]}#{prefix}#{type[open_start..]}"
          else
            corrected = hash_braces_at(type, tokens, opener_index, name_start, prefix) or return
          end
          replace_tag_type(corrector, comment, target.index, type, corrected)
        end

        def include_yard_tag?(comment)
          comment.source.match?(/@(?:param|return|option|raise|yieldparam|yieldreturn)\s+.*\[.*\]/)
        end

        def tag_range_for_comment(comment)
          # include_yard_tag? guarantees that the comment has `[...]`
          start_column = comment.source.index(/\[/) or raise "`[` is not found in #{comment.source}"
          end_column = comment.source.index(/\]/) or raise "`]` is not found in #{comment.source}"
          offense_start = comment.location.column + start_column + 1
          offense_end = comment.location.column + end_column
          source_range(processed_source.buffer, comment.location.line, offense_start..offense_end)
        end
      end
    end
  end
end
