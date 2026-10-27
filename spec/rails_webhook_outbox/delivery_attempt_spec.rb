require "rails_helper"

RSpec.describe RailsWebhookOutbox::DeliveryAttempt do
  let(:subscription) do
    RailsWebhookOutbox::Subscription.create!(url: "https://example.com/webhooks", events: ["order.created"])
  end
  let(:delivery) do
    RailsWebhookOutbox::Delivery.create!(subscription: subscription, event: "order.created", payload: { id: 1 })
  end

  describe "validations" do
    it "is valid with a delivery, attempt number and outcome" do
      attempt = described_class.new(delivery: delivery, attempt_number: 1, outcome: :delivered)
      expect(attempt).to be_valid
    end

    it "requires a delivery" do
      attempt = described_class.new(attempt_number: 1, outcome: :delivered)
      expect(attempt).not_to be_valid
    end

    it "requires an attempt number" do
      attempt = described_class.new(delivery: delivery, outcome: :delivered)
      expect(attempt).not_to be_valid
      expect(attempt.errors[:attempt_number]).to include("can't be blank")
    end
  end

  describe "outcome" do
    it "maps delivered and failed" do
      expect(described_class.outcomes).to eq("delivered" => 0, "failed" => 1)
    end
  end

  describe "Delivery#delivery_attempts" do
    it "returns attempts ordered by attempt number" do
      second = described_class.create!(delivery: delivery, attempt_number: 2, outcome: :delivered)
      first = described_class.create!(delivery: delivery, attempt_number: 1, outcome: :failed)

      expect(delivery.delivery_attempts).to eq([first, second])
    end

    it "deletes attempts when the delivery is destroyed" do
      described_class.create!(delivery: delivery, attempt_number: 1, outcome: :failed)

      expect { delivery.destroy! }.to change(described_class, :count).by(-1)
    end

    it "is cascaded by the database when deliveries are bulk-deleted" do
      described_class.create!(delivery: delivery, attempt_number: 1, outcome: :failed)

      expect { RailsWebhookOutbox::Delivery.where(id: delivery.id).delete_all }
        .to change(described_class, :count).by(-1)
    end
  end
end
