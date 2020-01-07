ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  # parallel tests deactivated due to database consistency problems, Ramm, 21.12.2019
  # parallelize(workers: :number_of_processors, with: :threads)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...
end

class ActionDispatch::IntegrationTest
  setup do
    # create JWT token for following tests
    user = User.first
    @jwt_token = token = JsonWebToken.encode({user_id: user.id}, 1.hours.from_now)
  end

  # provide JWT token for tests
  def jwt_header
    { 'Authorization' => @jwt_token}
  end
end

