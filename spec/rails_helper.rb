require "spec_helper"
require "webmock/rspec"
ENV["RAILS_ENV"] ||= "test"
require File.expand_path("../dummy/config/environment", __FILE__)
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

engine_migration_path = File.expand_path("../../db/migrate", __dir__)
ActiveRecord::Migrator.migrations_paths << engine_migration_path unless ActiveRecord::Migrator.migrations_paths.include?(engine_migration_path)
ActiveRecord::Tasks::DatabaseTasks.migrate

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("spec/fixtures")]
  config.use_transactional_fixtures = true
  config.filter_rails_from_backtrace!
end