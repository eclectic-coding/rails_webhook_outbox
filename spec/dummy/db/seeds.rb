RailsWebhookOutbox::Subscription.find_or_create_by!(url: "http://localhost:4000/webhooks") do |s|
  s.secret = "dev-secret-change-me"
  s.events = %w[order.created order.updated order.cancelled]
  s.description = "Local dev webhook receiver"
end

Order.create!(title: "Widget Pack", total: 49.99, status: "pending")
Order.create!(title: "Gadget Bundle", total: 129.00, status: "confirmed")
Order.create!(title: "Cancelled Order", total: 19.99, status: "cancelled", cancelled_at: Time.current)