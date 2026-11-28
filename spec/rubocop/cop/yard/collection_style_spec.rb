# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RuboCop::Cop::YARD::CollectionStyle, :config do
  # `[A, B]`, `A | B` and `A & B` parse only on yard 0.9.46 and later.
  GROUP_TYPES = defined?(YARD::Tags::TypesExplainer::GroupType)
  NEEDS_YARD_0_9_46 = 'needs yard 0.9.46 or later'

  context 'when EnforcedStyle is long' do
    let(:cop_config) { { 'EnforcedStyle' => 'long' } }

    it 'registers offenses and autocorrects short style to long style' do
      expect_offense(<<~RUBY)
        class Foo
          # @param [(Symbol)]
          ^^^^^^^^^^^^^^^^^^^ `(Symbol)` is using short style syntax
          # @param [<Symbol>]
          ^^^^^^^^^^^^^^^^^^^ `<Symbol>` is using short style syntax
          # @param [{Symbol => String}]
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `{Symbol => String}` is using short style syntax
          def foo
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo
          # @param [Array(Symbol)]
          # @param [Array<Symbol>]
          # @param [Hash{Symbol => String}]
          def foo
          end
        end
      RUBY
    end

    it 'does not register an offense for long style' do
      expect_no_offenses(<<~RUBY)
        class Foo
          # @param [Array(Symbol)]
          # @param [Array<Symbol>]
          # @param [Hash{Symbol => String}]
          # @param [Range<Integer>]
          # @param [Dict{Symbol=>String}]
          def foo
          end
        end
      RUBY
    end

    it 'handles complex nested types' do
      expect_offense(<<~RUBY)
        class Foo
          # @param [<<<Symbol>>>]
          ^^^^^^^^^^^^^^^^^^^^^^^ `<<<Symbol>>>` is using short style syntax
          # @param [Array<{Symbol => <Integer>, List<Integer>}>]
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `Array<{Symbol => <Integer>, List<Integer>}>` is using short style syntax
          def foo
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo
          # @param [Array<Array<Array<Symbol>>>]
          # @param [Array<Hash{Symbol => Array<Integer>, List<Integer>}>]
          def foo
          end
        end
      RUBY
    end

    it 'does not register an offense for grouped, union and intersection types' do
      expect_no_offenses(<<~RUBY)
        class Foo
          # @param [Array(Symbol, Array([Integer, nil], [Integer, nil]))]
          # @param [Array(Symbol, String, Array([Integer, nil], [Integer, nil]))]
          # @param [Array(Integer | nil, String)]
          # @param [Array<String | nil>]
          # @param [Foo & Bar]
          # @param [[Foo | Bar] & Baz]
          def foo
          end
        end
      RUBY
    end

    it 'does not register an offense for a named collection yard parses differently' do
      expect_no_offenses(<<~RUBY)
        class Foo
          # @param [Hash<Symbol, String>]
          # @param [Hash{Symbol => String; Integer => Float}]
          # @param [Hash<Symbol, Integer | nil>]
          # @param [Array<Hash<Symbol, String>>]
          # @param [Hash<Symbol, Hash<Symbol, String>>]
          # @param [Hash<'a, b', #to_s>]
          def foo
          end
        end
      RUBY
    end

    it 'leaves quoted literals and duck types as written' do
      expect_offense(<<~RUBY)
        class Foo
          # @param [Array<'a<b', "Hash{x">]
          # @param [Array<#to_s, #<=>>]
          # @param [<'a(b'>]
          ^^^^^^^^^^^^^^^^^^ `<'a(b'>` is using short style syntax
          # @param [<#[], #<<>]
          ^^^^^^^^^^^^^^^^^^^^^ `<#[], #<<>` is using short style syntax
          def foo
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo
          # @param [Array<'a<b', "Hash{x">]
          # @param [Array<#to_s, #<=>>]
          # @param [Array<'a(b'>]
          # @param [Array<#[], #<<>]
          def foo
          end
        end
      RUBY
    end

    it 'autocorrects only the collection name, keeping union spelling', skip: (NEEDS_YARD_0_9_46 unless GROUP_TYPES) do
      expect_offense(<<~RUBY)
        class Foo
          # @param [Array(<A> | B, C)]
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `Array(<A> | B, C)` is using short style syntax
          # @param [[A | <B>] & C]
          ^^^^^^^^^^^^^^^^^^^^^^^^ `[A | <B>] & C` is using short style syntax
          def foo
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo
          # @param [Array(Array<A> | B, C)]
          # @param [[A | Array<B>] & C]
          def foo
          end
        end
      RUBY
    end
  end

  context 'when EnforcedStyle is short' do
    let(:cop_config) { { 'EnforcedStyle' => 'short' } }

    it 'registers offenses and autocorrects long style to short style' do
      expect_offense(<<~RUBY)
        class Foo
          # @param [Array(Symbol)]
          ^^^^^^^^^^^^^^^^^^^^^^^^ `Array(Symbol)` is using long style syntax
          # @param [Array<Symbol>]
          ^^^^^^^^^^^^^^^^^^^^^^^^ `Array<Symbol>` is using long style syntax
          # @param [Hash{Symbol => String}]
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `Hash{Symbol => String}` is using long style syntax
          def foo
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo
          # @param [(Symbol)]
          # @param [<Symbol>]
          # @param [{Symbol => String}]
          def foo
          end
        end
      RUBY
    end

    it 'does not register an offense for short style' do
      expect_no_offenses(<<~RUBY)
        class Foo
          # @param [(Symbol)]
          # @param [<Symbol>]
          # @param [{Symbol => String}]
          def foo
          end
        end
      RUBY
    end

    it 'leaves quoted literals and duck types as written' do
      expect_offense(<<~RUBY)
        class Foo
          # @param [Array<'a<b', "Hash{x">]
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `Array<'a<b', "Hash{x">` is using long style syntax
          # @param [Array<#to_s, #<=>>]
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `Array<#to_s, #<=>>` is using long style syntax
          # @param [<'Array(b'>]
          def foo
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo
          # @param [<'a<b', "Hash{x">]
          # @param [<#to_s, #<=>>]
          # @param [<'Array(b'>]
          def foo
          end
        end
      RUBY
    end

    it 'keeps the name where the short form means something else' do
      expect_no_offenses(<<~RUBY)
        class Foo
          # @param [Hash(Symbol)]
          # @param [Array{Symbol => String}]
          # @param [Hash<Symbol>]
          # @param [Hash<A, B, C>]
          def foo
          end
        end
      RUBY
    end

    it 'rewrites Hash<K, V> to {K => V}' do
      expect_offense(<<~RUBY)
        class Foo
          # @param [Hash<Symbol, String>]
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `Hash<Symbol, String>` is using long style syntax
          def foo
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo
          # @param [{Symbol => String}]
          def foo
          end
        end
      RUBY
    end

    it 'rewrites nested Hash<K, V> keeping K and V as written' do
      expect_offense(<<~RUBY)
        class Foo
          # @param [Hash<Symbol, Integer | nil>]
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `Hash<Symbol, Integer | nil>` is using long style syntax
          # @param [Array<Hash<Symbol, String>>]
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `Array<Hash<Symbol, String>>` is using long style syntax
          # @param [Hash<Symbol, Hash<Symbol, String>>]
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `Hash<Symbol, Hash<Symbol, String>>` is using long style syntax
          # @param [Hash<'a, b', #to_s>]
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `Hash<'a, b', #to_s>` is using long style syntax
          def foo
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo
          # @param [{Symbol => Integer | nil}]
          # @param [<{Symbol => String}>]
          # @param [{Symbol => {Symbol => String}}]
          # @param [{'a, b' => #to_s}]
          def foo
          end
        end
      RUBY
    end

    it 'drops names from grouped and union types' do
      expect_offense(<<~RUBY)
        class Foo
          # @param [Array(Symbol, String, Array([Integer, nil], [Integer, nil]))]
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `Array(Symbol, String, Array([Integer, nil], [Integer, nil]))` is using long style syntax
          # @param [Array(Integer | nil, String)]
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `Array(Integer | nil, String)` is using long style syntax
          def foo
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo
          # @param [(Symbol, String, ([Integer, nil], [Integer, nil]))]
          # @param [(Integer | nil, String)]
          def foo
          end
        end
      RUBY
    end

    it 'autocorrects only the collection name, keeping union spelling', skip: (NEEDS_YARD_0_9_46 unless GROUP_TYPES) do
      expect_offense(<<~RUBY)
        class Foo
          # @param [(Symbol, [Array<Integer> | nil])]
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `(Symbol, [Array<Integer> | nil])` is using long style syntax
          def foo
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo
          # @param [(Symbol, [<Integer> | nil])]
          def foo
          end
        end
      RUBY
    end
  end

  context 'when YARD parses types into a different number of explainers' do
    let(:cop_config) { { 'EnforcedStyle' => 'long' } }

    # @see https://github.com/ksss/rubocop-yard/issues/43
    it 'does not register an offense or destructively autocorrect' do
      expect_no_offenses(<<~RUBY)
        class Foo
          # @return [Array<Hash{Symbol => String}>, nil]
          def foo
          end
        end
      RUBY
    end
  end

  it 'does not register an offense for a reference tag with brackets' do
    expect_no_offenses(<<~RUBY)
      class Foo
        # @param [String] (see #other)
        def foo(arg)
        end
      end
    RUBY
  end
end
