require "rails_helper"
require "openssl"

RSpec.describe RailsWebhookOutbox::Signature do
  let(:payload) { '{"event":"order.created","data":{"id":1}}' }
  let(:secret)  { "supersecret" }

  after { RailsWebhookOutbox.reset_configuration! }

  describe ".sign" do
    it "returns an HMAC hex digest using the given algorithm" do
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      expect(described_class.sign(payload, secret, :sha256)).to eq(expected)
    end

    it "supports sha384" do
      expected = OpenSSL::HMAC.hexdigest("SHA384", secret, payload)
      expect(described_class.sign(payload, secret, :sha384)).to eq(expected)
    end

    it "supports sha512" do
      expected = OpenSSL::HMAC.hexdigest("SHA512", secret, payload)
      expect(described_class.sign(payload, secret, :sha512)).to eq(expected)
    end

    it "produces different digests for different secrets" do
      a = described_class.sign(payload, "secret-a", :sha256)
      b = described_class.sign(payload, "secret-b", :sha256)
      expect(a).not_to eq(b)
    end

    it "produces different digests for different payloads" do
      a = described_class.sign("payload-a", secret, :sha256)
      b = described_class.sign("payload-b", secret, :sha256)
      expect(a).not_to eq(b)
    end
  end

  describe ".header_value" do
    it "returns a formatted sha256=<hex> string using the configured algorithm" do
      hex = described_class.sign(payload, secret, :sha256)
      expect(described_class.header_value(payload, secret)).to eq("sha256=#{hex}")
    end

    it "uses the configured signing algorithm" do
      RailsWebhookOutbox.configure { |c| c.signing_algorithm = :sha512 }
      hex = described_class.sign(payload, secret, :sha512)
      expect(described_class.header_value(payload, secret)).to eq("sha512=#{hex}")
    end

    it "signs with every secret when given an array" do
      hex_a = described_class.sign(payload, "secret-a", :sha256)
      hex_b = described_class.sign(payload, "secret-b", :sha256)
      expect(described_class.header_value(payload, ["secret-a", "secret-b"])).to eq("sha256=#{hex_a},sha256=#{hex_b}")
    end
  end
end
