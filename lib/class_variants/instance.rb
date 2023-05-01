module ClassVariants
  class Instance
    attr_reader :classes
    attr_reader :variants
    attr_reader :defaults
    attr_reader :variant_keys

    def initialize(classes = nil, variants: {}, defaults: {}, parent_variant_keys: variants.keys)
      @classes = classes
      @variants =
        variants
          .then { build_compound_variants(_1, parent_variant_keys:) }
          .then { expand_boolean_variants(_1) }
      @defaults = defaults
      @variant_keys = build_variant_keys
      @opt_cache = {}
    end

    def render(**overrides)
      @opt_cache.fetch(@defaults.merge(overrides).slice(*@variant_keys)) do |render_options|
        result = []

        # Start with our default classes
        result << @classes if @classes

        # Then merge the passed in overrides on top of the defaults
        render_options.each do |variant_type, variant|
            # dig the class definitions out
            case @variants.dig(variant_type, variant)
            in String => classes
              # If they're a string of classes, append them to the result
              result << classes
            in ClassVariants::Instance => compound_variants
              # If they're another class variants instance, render them and append
              result << compound_variants.render(**render_options)
            else
              # No-op
            end
          end

        @opt_cache[render_options] = result.join(" ").squeeze(" ").strip
      end
    end

    def possibilities
      variants.values.map { |variant_options|
        variant_options.values.sum do |variant_option|
          case variant_option
          when String then 1
          when Instance then variant_option.possibilities
          else
            raise "wat"
          end
        end
      }.reduce(:*)
    end

    private

    def build_compound_variants(variants, parent_variant_keys:)
      variants.transform_values do |variant_options|
        next variant_options if variant_options.is_a? String

        if variant_options.keys.all? { |compound_variant| parent_variant_keys.include?(compound_variant) }
          Instance.new(variants: variant_options, parent_variant_keys:)
        else
          variant_options.transform_values do |variant_option|
            case variant_option
            in Hash => variants
              Instance.new(variants:, parent_variant_keys:)
            in [String => base_classes, Hash => variants]
              Instance.new(base_classes, variants:, parent_variant_keys:)
            else
              variant_option
            end
          end
        end
      end
    end

    def expand_boolean_variants(variants)
      variants.each.map { |key, value|
        case value
        when String, Instance
          s_key = key.to_s
          { s_key.delete_prefix("!").to_sym => { !s_key.start_with?("!") => value } }
        else
          { key => value }
        end
      }.reduce { |variants, more_variants|
        variants.merge!(more_variants) { |_key, v1, v2| v1.merge!(v2) }
      }.delete_if { |key, _value|
        key.to_s.start_with?("!")
      }
    end

    def build_variant_keys
      keys = Set[]
      puts @variants
      @variants.each do |key, value|
        keys << key
        value.values.each do |variant_option_value|
          if variant_option_value.is_a?(Instance)
            keys += variant_option_value.variant_keys
          end
        end
      end
      keys
    end
  end
end
