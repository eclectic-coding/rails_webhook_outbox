require "rails_helper"

RSpec.describe RailsWebhookOutbox::Dispatchable do
  include ActiveJob::TestHelper

  before(:all) do
    ActiveRecord::Base.connection.create_table(:orders, force: true) do |t|
      t.string :title
      t.boolean :cancelled, default: false
      t.timestamps
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.drop_table(:orders, if_exists: true)
  end

  let(:model_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "orders"
      include RailsWebhookOutbox::Dispatchable
    end
  end

  let!(:subscription) do
    RailsWebhookOutbox::Subscription.create!(
      url: "https://example.com/hooks",
      events: ["order.created", "order.updated", "order.cancelled"],
      active: true
    )
  end

  describe ".dispatches_webhook" do
    context "on: :create" do
      before { model_class.dispatches_webhook "order.created", on: :create }

      it "enqueues DeliveryJob after create" do
        expect { model_class.create!(title: "Test") }
          .to have_enqueued_job(RailsWebhookOutbox::DeliveryJob)
      end

      it "creates a Delivery record" do
        expect { model_class.create!(title: "Test") }
          .to change(RailsWebhookOutbox::Delivery, :count).by(1)
      end

      it "does not enqueue on update" do
        order = model_class.create!(title: "Test")
        expect { order.update!(title: "New") }
          .not_to have_enqueued_job(RailsWebhookOutbox::DeliveryJob)
      end
    end

    context "on: :update" do
      before { model_class.dispatches_webhook "order.updated", on: :update }

      it "enqueues DeliveryJob after update" do
        order = model_class.create!(title: "Test")
        expect { order.update!(title: "New") }
          .to have_enqueued_job(RailsWebhookOutbox::DeliveryJob)
      end

      it "does not enqueue on create" do
        expect { model_class.create!(title: "Test") }
          .not_to have_enqueued_job(RailsWebhookOutbox::DeliveryJob)
      end
    end

    context "with if: condition" do
      before do
        model_class.dispatches_webhook "order.cancelled", on: :update,
          if: -> { cancelled? }
      end

      it "dispatches when the condition is true" do
        order = model_class.create!(title: "Test", cancelled: false)
        expect { order.update!(cancelled: true) }
          .to have_enqueued_job(RailsWebhookOutbox::DeliveryJob)
      end

      it "does not dispatch when the condition is false" do
        order = model_class.create!(title: "Test", cancelled: false)
        expect { order.update!(title: "Changed") }
          .not_to have_enqueued_job(RailsWebhookOutbox::DeliveryJob)
      end
    end
  end

  describe "subscription matching" do
    before { model_class.dispatches_webhook "order.created", on: :create }

    it "skips subscriptions that do not subscribe to the event" do
      RailsWebhookOutbox::Subscription.create!(
        url: "https://other.example.com/hooks",
        events: ["payment.completed"],
        active: true
      )
      expect { model_class.create!(title: "Test") }
        .to change(RailsWebhookOutbox::Delivery, :count).by(1)
    end

    it "skips inactive subscriptions" do
      subscription.update!(active: false)
      expect { model_class.create!(title: "Test") }
        .not_to have_enqueued_job(RailsWebhookOutbox::DeliveryJob)
    end

    it "enqueues a job for each matching subscription" do
      RailsWebhookOutbox::Subscription.create!(
        url: "https://second.example.com/hooks",
        events: ["order.created"],
        active: true
      )
      expect { model_class.create!(title: "Test") }
        .to have_enqueued_job(RailsWebhookOutbox::DeliveryJob).twice
    end
  end

  describe "payload size validation" do
    before do
      RailsWebhookOutbox.configure { |c| c.max_payload_size = 10 }
      model_class.dispatches_webhook "order.created", on: :create
    end

    after { RailsWebhookOutbox.reset_configuration! }

    it "raises PayloadSizeError when the payload exceeds the limit" do
      expect { model_class.create!(title: "A title that will exceed the ten byte limit") }
        .to raise_error(RailsWebhookOutbox::PayloadSizeError)
    end
  end

  describe "event validation" do
    before do
      RailsWebhookOutbox.configure { |c| c.events = %w[order.created] }
      model_class.dispatches_webhook "order.created", on: :create
    end

    after { RailsWebhookOutbox.reset_configuration! }

    it "raises ArgumentError when the event is not registered" do
      unregistered_class = Class.new(ActiveRecord::Base) do
        self.table_name = "orders"
        include RailsWebhookOutbox::Dispatchable
        dispatches_webhook "payment.failed", on: :create
      end

      expect { unregistered_class.create!(title: "Test") }
        .to raise_error(ArgumentError, /Unknown event "payment\.failed"/)
    end

    it "does not raise for a registered event" do
      expect { model_class.create!(title: "Test") }.not_to raise_error
    end
  end

  describe "#webhook_payload" do
    before { model_class.dispatches_webhook "order.created", on: :create }

    it "defaults to as_json" do
      order = model_class.new(title: "Test")
      expect(order.webhook_payload).to eq(order.as_json)
    end

    it "stores the record attributes on the delivery" do
      model_class.create!(title: "My Order")
      expect(RailsWebhookOutbox::Delivery.last.payload["title"]).to eq("My Order")
    end

    it "uses a custom payload when overridden" do
      custom_class = Class.new(ActiveRecord::Base) do
        self.table_name = "orders"
        include RailsWebhookOutbox::Dispatchable
        dispatches_webhook "order.created", on: :create
        def webhook_payload = { title: title }
      end

      custom_class.create!(title: "Custom")
      expect(RailsWebhookOutbox::Delivery.last.payload).to eq({ "title" => "Custom" })
    end
  end
end
