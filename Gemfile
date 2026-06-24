source "https://rubygems.org"

# Specify your gem's dependencies in rails_webhook_outbox.gemspec.
gemspec

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

# Start debugger with binding.b [https://github.com/ruby/debug]
# gem "debug", ">= 1.0.0"

group :development do
  gem "rubocop-rails-omakase", require: false
  gem "bundler-audit"
end

group :development, :test do
  gem "puma"
  gem "sqlite3"
  gem "propshaft"
end

group :test do
  gem "rspec-rails"
  gem "simplecov", require: false
  gem "simplecov_json_formatter", require: false
end
