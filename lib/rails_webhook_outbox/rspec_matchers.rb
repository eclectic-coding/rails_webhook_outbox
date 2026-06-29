require "rails_webhook_outbox/testing"

RSpec::Matchers.define :dispatch_webhook do |expected_event|
  chain :with_payload do |payload|
    @expected_payload = payload
  end

  match do |block|
    before = RailsWebhookOutbox::Testing.deliveries.dup
    block.call
    @dispatched = RailsWebhookOutbox::Testing.deliveries.drop(before.size)
    @dispatched.any? do |d|
      d[:event] == expected_event.to_s &&
        (@expected_payload.nil? || d[:payload] == @expected_payload)
    end
  end

  supports_block_expectations

  failure_message do
    if @dispatched.empty?
      "expected #{expected_event.inspect} webhook to be dispatched, but no webhooks were dispatched"
    else
      events = @dispatched.map { |d| d[:event].inspect }.join(", ")
      "expected #{expected_event.inspect} webhook to be dispatched, but dispatched: #{events}"
    end
  end

  failure_message_when_negated do
    "expected #{expected_event.inspect} webhook not to be dispatched, but it was"
  end
end
