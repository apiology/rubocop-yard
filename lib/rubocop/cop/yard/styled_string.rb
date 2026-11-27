# frozen_string_literal: true

module RuboCop
  module Cop
    module YARD
      # Renders a type of YARD in the collection style configured by `EnforcedStyle`.
      module StyledString
        def styled_string(types_explainer)
          case types_explainer
          when ::YARD::Tags::TypesExplainer::HashCollectionType
            tname = case [style, types_explainer.name]
            when [:short, 'Hash']
              ''
            when [:long, 'Hash']
              'Hash'
            else
              types_explainer.name
            end
            "#{tname}{#{types_explainer.key_types.map { styled_string(_1) }.join(', ')} => #{types_explainer.value_types.map { styled_string(_1) }.join(', ')}}"
          when ::YARD::Tags::TypesExplainer::FixedCollectionType
            tname = case [style, types_explainer.name]
            when [:short, 'Array']
              ''
            when [:long, 'Array']
              'Array'
            else
              types_explainer.name
            end
            "#{tname}(#{types_explainer.types.map { styled_string(_1) }.join(', ')})"
          when ::YARD::Tags::TypesExplainer::CollectionType
            tname = case [style, types_explainer.name]
            when [:short, 'Array']
              ''
            when [:long, 'Array']
              'Array'
            else
              types_explainer.name
            end
            "#{tname}<#{types_explainer.types.map { styled_string(_1) }.join(', ')}>"
          when ::YARD::Tags::TypesExplainer::Type
            # GroupType and IntersectionType have no name and need yard 0.9.46 or later.
            if defined?(::YARD::Tags::TypesExplainer::GroupType) &&
               types_explainer.is_a?(::YARD::Tags::TypesExplainer::GroupType)
              "[#{types_explainer.types.map { styled_string(_1) }.join(', ')}]"
            elsif defined?(::YARD::Tags::TypesExplainer::IntersectionType) &&
                  types_explainer.is_a?(::YARD::Tags::TypesExplainer::IntersectionType)
              types_explainer.types.map { styled_string(_1) }.join(' & ')
            else
              types_explainer.name
            end
          else
            raise "#{types_explainer.class} is not supported"
          end
        end
      end
    end
  end
end
