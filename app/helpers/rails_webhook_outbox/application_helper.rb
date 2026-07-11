module RailsWebhookOutbox
  module ApplicationHelper
    def inline_styles
      dir = RailsWebhookOutbox::Engine.root.join("app/assets/stylesheets/rails_webhook_outbox")
      css = dir.glob("_*.css").sort.map(&:read).join("\n")
      content_tag(:style, css.html_safe)
    end

    def status_badge(status)
      css_class = case status.to_s
      when "delivered" then "rwo-badge--delivered"
      when "failed"    then "rwo-badge--failed"
      else                  "rwo-badge--pending"
      end
      content_tag(:span, status.to_s.capitalize, class: "rwo-badge #{css_class}")
    end

    def active_badge(active)
      css_class = active ? "rwo-badge--delivered" : "rwo-badge--failed"
      content_tag(:span, active ? "Active" : "Disabled", class: "rwo-badge #{css_class}")
    end

    def masked_secret(secret)
      return "" if secret.blank?

      "#{"•" * 8}#{secret.last(4)}"
    end
  end
end
