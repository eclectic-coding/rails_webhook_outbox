require "rails_helper"
require "rails_webhook_outbox/rspec_matchers"

RSpec.describe "dispatch_webhook matcher" do
  before do
    RailsWebhookOutbox.configure { |c| c.test_mode = true }
    RailsWebhookOutbox::Testing.clear_deliveries!
  end

  after { RailsWebhookOutbox.reset_configuration! }

  it "passes when the expected event is dispatched" do
    expect { RailsWebhookOutbox.dispatch("order.created", { id: 1 }) }
      .to dispatch_webhook("order.created")
  end

  it "passes with with_payload when the payload matches" do
    expect { RailsWebhookOutbox.dispatch("order.created", { id: 1 }) }
      .to dispatch_webhook("order.created").with_payload({ id: 1 })
  end

  it "fails with with_payload when the payload does not match" do
    expect {
      expect { RailsWebhookOutbox.dispatch("order.created", { id: 2 }) }
        .to dispatch_webhook("order.created").with_payload({ id: 1 })
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  it "fails when no webhooks are dispatched" do
    expect {
      expect { nil }.to dispatch_webhook("order.created")
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /no webhooks were dispatched/)
  end

  it "fails when a different event is dispatched" do
    expect {
      expect { RailsWebhookOutbox.dispatch("order.updated", { id: 1 }) }
        .to dispatch_webhook("order.created")
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /"order.updated"/)
  end

  it "supports negation when no event is dispatched" do
    expect { nil }.not_to dispatch_webhook("order.created")
  end

  it "fails negation when the event is dispatched" do
    expect {
      expect { RailsWebhookOutbox.dispatch("order.created", { id: 1 }) }
        .not_to dispatch_webhook("order.created")
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /not to be dispatched/)
  end
end
