require 'net/http'
require 'uri'
require 'json'

class IntegrationTestStarter < ActiveSupport::TestCase

  def initialize
    super('IntegrationTestStarter')
    Rails.logger = ActiveSupport::Logger.new(STDOUT)
    @api_token = nil
  end

  # Run the whole test suite with MOVEX CDC Docker container and Kafka
  # Needed environment:
  def run
    puts "IntegrationTestStarter.run"
    db_config = Rails.application.config.database_configuration
    ActiveRecord::Base.establish_connection(db_config['test'])
    Database.initialize_db_connection                                              # do some init actions for DB connection before use
    configure_schema

  end

  # Configure the schema for the integration test using MOVEX CDC API
  def configure_schema
    load_api_token

  end

  def load_api_token
    response = execute_post_request('login/do_logon', { email: "admin", password: MovexCdc::Application.config.db_password})
    assert_not_nil(response, "Response should not be nil")
    @api_token = response['token']
    assert_not_nil(@api_token, 'API token should not be nil')
    puts @api_token
  end

  # Call API with POST request
  # @param url [String] URL of the API
  # @param params [Hash] Parameters for the API
  # @return [Hash] Response from the API
  def execute_post_request(url, params)
    uri = URI.parse("http://localhost:8080/#{url}")
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request.body = JSON.dump(params)

    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end
    JSON.parse(response.body)
  end
end


