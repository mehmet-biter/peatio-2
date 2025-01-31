# frozen_string_literal: true

# Copyright (c) 2019 Danil Pismenny <danil@brandymint.ru>
class Money
  def base_units
    fractional
  end

  # We often use in on loggin this way
  def as_json
    {
      fractional: fractional.to_i,
      currency_id: currency.id
    }
  end

  class Currency
    module Loader
      def self.load!(_options = nil)
        @currencies = {}
      end
    end

    include NumericHelpers

    class << self
      def find!(id)
        find(id) || raise("No #{id} Money::Currency found!")
      end

      def all
        ::BlockchainCurrency.all.map(&:money_currency)
      end

      def new(id)
        id = id.to_s.downcase
        RequestStore.store['money_currency_' + id] ||= super(id).freeze
      end
    end

    attr_reader :blockchain_currency_record, :currency_record

    delegate :base_factor, :subunit_to_unit, :min_deposit_amount, :blockchain, :options, :token?, :contract_address, to: :blockchain_currency_record
    delegate :priority, :precision, :name, :min_collection_amount, :crypto?, to: :currency_record

    def initialize_data!
      @blockchain_currency_record = ::BlockchainCurrency.find(id.to_s.to_i)
      @currency_record = @blockchain_currency_record.currency
    rescue ActiveRecord::RecordNotFound
      raise UnknownCurrency, id
    end

    def iso_code
      id
    end

    # TODO: rename from_units_to_money
    def to_money_from_decimal(value)
      raise "Value must be an Decimal (#{value})" unless value.is_a? BigDecimal

      value.to_money(self).freeze
    end

    def to_money_from_units(value)
      raise "Value must be an Integer (#{value})" unless value.is_a? Integer

      Money.new(value, self).freeze
    end

    def convert_to_base_unit(value)
      x = value.to_d * base_factor
      unless (x % 1).zero?
        raise "Failed to convert currency (#{self}) value to base (smallest) unit because it exceeds the maximum precision: " \
              "#{value.to_d} - #{x.to_d} must be equal to zero."
      end
      x.to_i
    end

    def zero_money
      0.to_money self
    end
  end
end
Money.locale_backend = :i18n
Money.default_currency = :RUB
Money.default_bank = nil
Money.rounding_mode = BigDecimal::ROUND_HALF_EVEN

# CURRENCIES_PATH = Rails.root.join './config/money_currencies.yml'

# currencies = Psych
# .load(File.read(CURRENCIES_PATH))
# .each_with_object({}) { |values, hash| hash[values.first.to_sym] = values.second.symbolize_keys.reverse_merge(iso_code: values.first.upcase) }
# .each_with_index { |data, index| data.second.reverse_merge! priority: index }

# Money::Currency::Loader.load! currencies
# Money::Currency.all
