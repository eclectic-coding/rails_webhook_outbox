class Order < ApplicationRecord
  include RailsWebhookOutbox::Dispatchable

  dispatches_webhook "order.created", on: :create
  dispatches_webhook "order.updated", on: :update, if: -> { !cancelled_at_previously_changed? }
  dispatches_webhook "order.cancelled", on: :update, if: -> { cancelled_at_previously_changed? && cancelled_at.present? }

  validates :title, presence: true
  validates :total, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: %w[pending confirmed shipped cancelled] }
end