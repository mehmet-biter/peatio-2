# frozen_string_literal: true

# TODO: Rename to DepositAddress
class PaymentAddress < ApplicationRecord
  extend PaymentAddressTotals
  include Vault::EncryptedModel
  include AASM

  strip_attributes

  vault_lazy_decrypt!

  after_commit :enqueue_address_generation

  validates :address, uniqueness: { scope: :blockchain_id }, if: :address?

  vault_attribute :details, serialize: :json, default: {}
  vault_attribute :secret

  scope :by_address, ->(address) { where('lower(address)=?', address.downcase) }
  scope :with_balances, -> { where 'EXISTS ( SELECT * FROM jsonb_each_text(balances) AS each(KEY,val) WHERE "val"::decimal >= 0)' }
  scope :collection_required, -> { with_balances.where(collection_state: %i[none pending done]) }

  # TODO: Migrate association from wallet to blockchain and remove Wallet.deposit*
  belongs_to :member
  belongs_to :blockchain

  aasm :collection_state, namespace: :collection, whiny_transitions: true, requires_lock: true do
    state :none, initial: true
    state :pending
    state :collecting
    state :gas_refueling
    state :done

    event :collect do
      transitions from: %i[pending none done], to: :collecting
      after do
        blockchain.gateway.collect! self
        done!
      end
    end

    event :refuel_gas do
      transitions from: %i[pending none done], to: :gas_refueling
      after do
        blockchain.gateway.refuel_gas! self
        done!
      end
    end

    event :done do
      transitions from: %i[collecting gas_refueling], to: :done
    end
  end

  before_validation if: :address do
    self.address = blockchain.normalize_address address if blockchain.present?
  end

  delegate :gateway, :currencies, to: :blockchain

  def self.find_by_address(address)
    where('lower(address)=?', address.downcase).take
  end

  def enqueue_address_generation
    AMQP::Queue.enqueue(:deposit_coin_address, { member_id: member.id, blockchain_id: blockchain_id }, { persistent: true })
  rescue Bunny::ConnectionClosedError => e
    report_exception e, true, member_id: member.id, blockchain_id: blockchain_id
  end

  def address_url
    blockchain&.explore_address_url address
  end

  def update_balances!
    Jobs::Cron::PaymentAddressBalancer.update_balances self
  end

  def format_address(format)
    blockchain.gateway_class.format_address(address, format)
  end

  def status
    if address.present?
      blockchain.status # active or disabled
    else
      'pending'
    end
  end

  def has_enough_gas_to_collect?
    blockchain.gateway.has_enough_gas_to_collect? address
  end

  # Balance reached amount limit to be collected
  def has_collectable_balances?
    blockchain.gateway.has_collectable_balances? address
  end

  def transactions
    if address.nil?
      Transaction.none
    else
      return Transaction.none if blockchain.nil?

      # TODO: blockchain normalize
      blockchain.transactions.by_address(address.downcase)
    end
  end

  def trigger_address_event
    ::AMQP::Queue.enqueue_event('private', member.uid, :deposit_address,
                                type: :create,
                                currencies: currencies.codes,
                                address: address)
  end

  def currency
    wallet.native_currency
  end
end
