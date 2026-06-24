require_relative "lib/rails_webhook_outbox/version"

Gem::Specification.new do |spec|
  spec.name        = "rails_webhook_outbox"
  spec.version     = RailsWebhookOutbox::VERSION
  spec.authors     = ["Chuck Smith"]
  spec.email       = ["eclectic-coding@users.noreply.github.com"]
  spec.homepage    = "https://github.com/eclectic-coding/rails_webhook_outbox"
  spec.summary     = "Outgoing webhooks for Rails with HMAC signing and ActiveJob retry"
  spec.description = "A Rails engine for sending outgoing webhooks with HMAC signing, ActiveJob-based retry, delivery logging, and a mountable dashboard."
  spec.license     = "MIT"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/eclectic-coding/rails_webhook_outbox"
  spec.metadata["changelog_uri"] = "https://github.com/eclectic-coding/rails_webhook_outbox/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.1.3"
end
