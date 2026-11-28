# frozen_string_literal: true

module RuboCop
  module Cop
    module YARD
      module Helper
        # A quoted literal or duck type, which is never edited.
        LITERAL = /'[^']*'|"[^"]*"|\##{::YARD::CodeObjects::METHODNAMEMATCH}/

        # Names, brackets and commas of a type, outside literals and `=>`.
        STRUCTURE = /(?<skip>#{LITERAL}|=>)|(?<name>[\w:]+)|(?<open>[<({\[])|(?<close>[>)}\]])|(?<comma>,)/

        def extract_tag_types(tag)
          case tag
          when ::YARD::Tags::OptionTag
            tag.pair.types
          when ::YARD::Tags::OverloadTag
            tag.types
          when ::YARD::Tags::RefTagList
            # A reference tag such as `@param [String] (see #other)` has no types of its own
            nil
          else
            tag.types
          end
        end

        def parse_type(type)
          ::YARD::Tags::TypesExplainer::Parser.parse(type)
        end

        def each_types_explainer(docstring, &block)
          docstring.tags.each do |tag|
            types = extract_tag_types(tag) or next

            begin
              types_explainers = parse_type(types.join(', '))
              next if types.size != types_explainers.size

              types.each_with_index do |type, i|
                block.call(type, types_explainers.fetch(i), i)
              end
            rescue SyntaxError
            end
          end
        end

        # @return [Array<Array(Symbol, Integer, Integer)>] the kind, start and
        #   end of each name, bracket and comma in +source+
        def type_tokens(source)
          tokens = []
          source.scan(STRUCTURE) do
            match = Regexp.last_match or next
            kind = %i[name open close comma].find { match[_1] } or next
            tokens << [kind, match.begin(0), match.end(0)]
          end
          tokens
        end

        # @return [Array(Integer, Array<Integer>), nil] for the bracket that
        #   tokens[index] opens, the index of its closing token and of each
        #   comma directly inside it
        def bracket_span(tokens, index)
          depth = 0
          commas = []
          (index...tokens.size).each do |i|
            kind, = tokens.fetch(i)
            depth += 1 if kind == :open
            depth -= 1 if kind == :close
            commas << i if kind == :comma && depth == 1
            return [i, commas] if depth.zero?
          end
          nil
        end

        # @return [Array<Array(Integer, Integer)>] for each collection opener
        #   (`<`, `(` or `{`) in +type+, where its name starts (the opener
        #   itself if it has none) and its index in +tokens+, in the order
        #   {#collection_nodes} lists them
        def collection_openers(type, tokens)
          openers = []
          tokens.each_with_index do |(kind, start, _), i|
            next unless kind == :open && type[start] != '['

            previous = i.positive? ? tokens[i - 1] : nil
            named = previous && previous[0] == :name && type[previous[2]...start].to_s.strip.empty?
            openers << [named && previous ? previous[1] : start, i]
          end
          openers
        end

        # @return [Array<::YARD::Tags::TypesExplainer::Type>] every collection
        #   in the parse tree, each before the ones inside it, which is the
        #   order their openers appear in the type
        def collection_nodes(types_explainer)
          case types_explainer
          when ::YARD::Tags::TypesExplainer::HashCollectionType
            children = types_explainer.key_value_pairs.flatten
          when ::YARD::Tags::TypesExplainer::CollectionType
            children = types_explainer.types
          else
            return group_members(types_explainer).flat_map { collection_nodes(_1) }
          end
          [types_explainer, *children.flat_map { collection_nodes(_1) }]
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

        # Rewrites the collection that tokens[index] opens, whose name starts
        # at name_start, as `<prefix>{K => V}`, keeping K and V as written.
        # @return [String, nil] nil unless it has exactly two slots
        def hash_braces_at(type, tokens, index, name_start, prefix)
          open_token = tokens[index] or return
          span = bracket_span(tokens, index) or return
          open_end = open_token[2]
          close, commas = span
          comma = commas.first
          return unless commas.size == 1 && comma

          _, comma_start, comma_end = tokens.fetch(comma)
          _, close_start, close_end = tokens.fetch(close)
          key = type[open_end...comma_start].to_s.strip
          value = type[comma_end...close_start].to_s.strip
          "#{type[0...name_start]}#{prefix}{#{key} => #{value}}#{type[close_end..]}"
        end

        # Replaces the index-th type in the comment's `[...]` with +corrected+,
        # keeping the tag's other types and the rest of the comment. Does
        # nothing if that type can't be found where yard's list puts it.
        def replace_tag_type(corrector, comment, index, type, corrected)
          source = comment.source
          tokens = type_tokens(source)
          open = tokens.index { |kind, start, _| kind == :open && source[start] == '[' } or return
          span = bracket_span(tokens, open) or return
          close, commas = span
          bounds = [tokens.fetch(open)[2]]
          commas.each { |i| bounds.push(tokens.fetch(i)[1], tokens.fetch(i)[2]) }
          bounds << tokens.fetch(close)[1]
          from = bounds[index * 2] or return
          to = bounds[(index * 2) + 1] or return
          segment = source[from...to].to_s
          return unless segment.strip == type

          corrector.replace(comment, "#{source[0...from]}#{segment[/\A\s*/]}#{corrected}#{segment[/\s*\z/]}#{source[to..]}")
        end

        # @return [Array(Integer, Integer), nil] where the tag's type list
        #   opens (`[`) and closes (its matching `]`) in +source+. Literals and
        #   duck types are skipped, and only square brackets count, so this
        #   holds even when the types inside don't parse.
        def tag_type_bounds(source)
          depth = 0
          open = nil
          type_tokens(source).each do |kind, start, _|
            char = source[start]
            next unless (kind == :open && char == '[') || (kind == :close && char == ']')
            next if open.nil? && char == ']'

            open ||= start
            depth += char == '[' ? 1 : -1
            return [open, start] if depth.zero?
          end
          nil
        end

        # The tag's types, from after its `[` through its matching `]`.
        def tag_range_for_comment(comment)
          # include_yard_tag? guarantees that the comment has `[...]`
          bounds = tag_type_bounds(comment.source)
          start_column = bounds ? bounds[0] : comment.source.index(/\[/)
          end_column = bounds ? bounds[1] : comment.source.index(/\]/)
          raise "`[...]` is not found in #{comment.source}" unless start_column && end_column

          offense_start = comment.location.column + start_column + 1
          offense_end = comment.location.column + end_column
          source_range(processed_source.buffer, comment.location.line, offense_start..offense_end)
        end

        def inline_comment?(comment)
          !comment_line?(comment.source_range.source_line)
        end

        def build_docstring(preceding_lines)
          comment_texts = preceding_lines.map { |l| l.text.gsub(/\A#/, '') }
          minimum_space = comment_texts.map { |t| t.index(/[^\s]/) }.compact.min
          yard_docstring = comment_texts.map { |t| t[minimum_space..-1] }.join("\n")
          begin
            ::YARD::Logger.instance.enter_level(::YARD::Logger::ERROR) do
              ::YARD::DocstringParser.new.parse(yard_docstring)
            end
          rescue
            nil
          end
        end
      end
    end
  end
end
