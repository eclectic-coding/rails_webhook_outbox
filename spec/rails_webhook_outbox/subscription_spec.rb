require "rails_helper"

RSpec.describe RailsWebhookOutbox::Subscription do
  subject(:subscription) do
    described_class.new(
      url: "https://example.com/webhooks",
      events: ["order.created"]
    )
  end

  describe "validations" do
    it "is valid with a url and events" do
      expect(subscription).to be_valid
    end

    context "url" do
      it "is invalid without a url" do
        subscription.url = nil
        expect(subscription).not_to be_valid
        expect(subscription.errors[:url]).to include("can't be blank")
      end

      it "is invalid with a non-HTTP url" do
        subscription.url = "ftp://example.com/hooks"
        expect(subscription).not_to be_valid
        expect(subscription.errors[:url]).to include("must be a valid HTTP or HTTPS URL")
      end

      it "accepts http urls" do
        subscription.url = "http://example.com/webhooks"
        expect(subscription).to be_valid
      end

      it "accepts https urls" do
        subscription.url = "https://example.com/webhooks"
        expect(subscription).to be_valid
      end
    end

    context "events" do
      it "is invalid without events" do
        subscription.events = nil
        expect(subscription).not_to be_valid
        expect(subscription.errors[:events]).to include("can't be blank")
      end

      it "is invalid with an empty events array" do
        subscription.events = []
        expect(subscription).not_to be_valid
        expect(subscription.errors[:events]).to include("can't be blank")
      end
    end

    context "secret" do
      it "is invalid if secret is explicitly set to nil after creation" do
        subscription.save!
        subscription.secret = nil
        expect(subscription).not_to be_valid
        expect(subscription.errors[:secret]).to include("can't be blank")
      end
    end
  end

  describe "auto-generated secret" do
    it "generates a secret on create when none is provided" do
      subscription.save!
      expect(subscription.secret).to be_present
      expect(subscription.secret.length).to eq(64)
    end

    it "does not overwrite a manually set secret" do
      subscription.secret = "my-custom-secret"
      subscription.save!
      expect(subscription.secret).to eq("my-custom-secret")
    end
  end

  describe ".active scope" do
    it "returns only active subscriptions" do
      active = described_class.create!(url: "https://a.example.com/hooks", events: ["order.created"], active: true)
      inactive = described_class.create!(url: "https://b.example.com/hooks", events: ["order.updated"], active: false)

      result = described_class.active

      expect(result).to include(active)
      expect(result).not_to include(inactive)
    end
  end

  describe "#subscribes_to?" do
    before { subscription.save! }

    it "returns true when the event is in the events list" do
      expect(subscription.subscribes_to?("order.created")).to be(true)
    end

    it "returns false when the event is not in the events list" do
      expect(subscription.subscribes_to?("order.updated")).to be(false)
    end

    it "accepts symbol arguments" do
      expect(subscription.subscribes_to?(:"order.created")).to be(true)
    end
  end
end