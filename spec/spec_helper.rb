# frozen_string_literal: true

$LOAD_PATH << "." unless $LOAD_PATH.include?(".")

require "rubygems"
require "bundler/setup"
require "timecop"
require "simplecov"
require "sidekiq"
require "rspec-sidekiq"
require "support/test_workers"

SimpleCov.start do
  add_filter "spec"
end

require "sidekiq/grouping"

Sidekiq::Grouping.logger = nil
Sidekiq.redis = { db: ENV.fetch("db", 1) }
Sidekiq.logger = nil

RSpec::Sidekiq.configure do |config|
  config.clear_all_enqueued_jobs = true
  config.warn_when_jobs_not_processed_by_sidekiq = false
end

RSpec.configure do |config|
  config.order = :random
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  config.before do
    Sidekiq.redis do |conn|
      keys = conn.keys "*batching*"
      keys.each { |key| conn.del key }
    end
  end

  config.after do
    Timecop.return
  end
end

$LOAD_PATH << File.join(File.dirname(__FILE__), "..", "lib")
