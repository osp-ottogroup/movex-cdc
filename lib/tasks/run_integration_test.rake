require_relative '../../test/integration/integration_test_starter'

namespace :test do
  task :run_integration_test do
    puts "Run integration test"
    IntegrationTestStarter.new.run
  end
end