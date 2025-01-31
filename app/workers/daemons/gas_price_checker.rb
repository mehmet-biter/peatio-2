# frozen_string_literal: true

module Workers
  module Daemons
    class GasPriceChecker < Base
      @sleep_time = 30.seconds

      THRESHOLD_DEVIATION_RATIO = 0.02

      def process
        return if Rails.env.staging?  # Стейджи не имеют доступа в шлюзы

        ::Blockchain.active.find_each do |blockchain|
          max_gas_price = Rails.configuration.blockchains.dig(blockchain.key, 'max_gas_price')
          next if !blockchain.gateway.is_a?(EthereumGateway) || max_gas_price.nil? || (blockchain.high_transaction_price_at.present? && blockchain.high_transaction_price_at > 5.minutes.ago)

          min_threshold = max_gas_price * (1 - THRESHOLD_DEVIATION_RATIO)
          max_threshold = max_gas_price * (1 + THRESHOLD_DEVIATION_RATIO)
          gas_price = EthereumGateway::AbstractCommand.new(blockchain.gateway.client).fetch_gas_price
          Rails.logger.info("Current gas price for #{blockchain.name}: #{gas_price * 1e-9} Gwei")
          if gas_price < min_threshold && !blockchain.high_transaction_price_at.nil?
            blockchain.update!(high_transaction_price_at: nil)
            Peatio::SlackNotifier.gas_price.ping "Включил выводы для #{blockchain.name}. Цена газа #{gas_price * 1e-9} Gwei ниже, чем #{min_threshold * 1e-9} Gwei."
          elsif gas_price > max_threshold && blockchain.high_transaction_price_at.nil?
            blockchain.update!(high_transaction_price_at: Time.current)
            Peatio::SlackNotifier.gas_price.ping "Отключил выводы для #{blockchain.name}. Цена газа #{gas_price * 1e-9} Gwei выше, чем #{max_threshold * 1e-9} Gwei."
          end
        rescue StandardError => e
          report_exception e, true, { service: 'GasPriceChecker' }
          next
        end
      end
    end
  end
end
