RailsWebhookOutbox::Subscription.find_or_create_by!(url: "http://localhost:4000/webhooks") do |s|
  s.secret = "dev-secret-change-me"
  s.events = %w[order.created order.updated order.cancelled]
  s.description = "Local dev webhook receiver"
end

Order.find_or_create_by!(title: "Widget Pack") { |o| o.total = 49.99; o.status = "pending" }
Order.find_or_create_by!(title: "Gadget Bundle") { |o| o.total = 129.00; o.status = "confirmed" }
Order.find_or_create_by!(title: "Cancelled Order") { |o| o.total = 19.99; o.status = "cancelled"; o.cancelled_at = Time.current }