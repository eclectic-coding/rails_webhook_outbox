require "rails_helper"

RSpec.describe RailsWebhookOutbox::Testing do
  before do
    RailsWebhookOutbox.configure { |c| c.test_mode = true }
    described_class.clear_deliveries!
  end

  after { RailsWebhookOutbox.reset_configuration! }

  describe ".deliveries" do
    it "starts empty after clear" do
      expect(described_class.deliveries).to be_empty
    end

    it "is memoized as an array" do
      expect(described_class.deliveries).to be_a(Array)
      expect(described_class.deliveries).to be(described_class.deliveries)
    end
  end

  describe ".clear_deliveries!" do
    it "empties the deliveries array" do
      described_class.deliveries << { event: "order.created", payload: {} }
      described_class.clear_deliveries!
      expect(described_class.deliveries).to be_empty
    end
  end

  describe "dispatch integration" do
    it "records dispatched events when test_mode is on" do
      RailsWebhookOutbox.dispatch("order.created", { id: 1 })
      expect(described_class.deliveries).to include({ event: "order.created", payload: { id: 1 } })
    end

    it "does not create Delivery records in test_mode" do
      expect { RailsWebhookOutbox.dispatch("order.created", { id: 1 }) }
        .not_to change(RailsWebhookOutbox::Delivery, :count)
    end

    it "records the event as a string regardless of input type" do
      RailsWebhookOutbox.dispatch("order.created", {})
      expect(described_class.deliveries.last[:event]).to eq("order.created")
    end
  end
end
