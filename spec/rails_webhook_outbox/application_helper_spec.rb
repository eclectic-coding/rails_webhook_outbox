require "rails_helper"

RSpec.describe RailsWebhookOutbox::ApplicationHelper, type: :helper do
  describe "#status_badge" do
    it "renders a delivered badge" do
      expect(helper.status_badge("delivered")).to include("rwo-badge--delivered", "Delivered")
    end

    it "renders a failed badge" do
      expect(helper.status_badge("failed")).to include("rwo-badge--failed", "Failed")
    end

    it "renders a pending badge for any other status" do
      expect(helper.status_badge("pending")).to include("rwo-badge--pending", "Pending")
    end
  end

  describe "#active_badge" do
    it "renders an active badge when true" do
      expect(helper.active_badge(true)).to include("rwo-badge--delivered", "Active")
    end

    it "renders a disabled badge when false" do
      expect(helper.active_badge(false)).to include("rwo-badge--failed", "Disabled")
    end
  end

  describe "#masked_secret" do
    it "masks all but the last 4 characters" do
      expect(helper.masked_secret("abcdef1234")).to eq("••••••••1234")
    end

    it "returns an empty string when the secret is blank" do
      expect(helper.masked_secret(nil)).to eq("")
    end
  end

  describe "#inline_styles" do
    it "renders a style tag containing the stylesheet partials" do
      expect(helper.inline_styles).to include("<style>", "rwo-badge")
    end
  end
end
