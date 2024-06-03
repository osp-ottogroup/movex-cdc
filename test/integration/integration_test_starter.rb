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
    create_test_structures
    configure_schema

  end

  def drop_table_if_exists(table_name)
    Database.execute("DROP TABLE #{table_name}", options: {no_exception_logging: true})
  rescue
    nil
  end

  # create the tables for the integration test
  def create_test_structures
    drop_table_if_exists('test_table1')
    Database.execute("CREATE TABLE test_table1 (id NUMBER PRIMARY KEY, name VARCHAR2(255))")
  end


  # Configure the schema for the integration test using MOVEX CDC API
  def configure_schema
    clear_configuration
    load_api_token
    schema = add_schema_to_config
    add_schema_rights_to_config(schema)
    add_table_to_config({
                          schema_id: schema['id'],
                          name: 'TEST_TABLE1'
                        }
    )
  end

  # Clear the MOVEX CDC configuration
  def clear_configuration
    Database.execute("DELETE FROM Columns")
    Database.execute("DELETE FROM Conditions")
    Database.execute("DELETE FROM Statistics")
    Database.execute("DELETE FROM Event_Logs")
    Database.execute("DELETE FROM Event_Log_Final_Errors")
    Database.execute("DELETE FROM Tables")
    Database.execute("DELETE FROM Schema_Rights")
    Database.execute("DELETE FROM Activity_Logs")
    Database.execute("DELETE FROM Users WHERE email != 'admin'")
    Database.execute("DELETE FROM Schemas")
    Database.execute("DELETE FROM Encryption_Key_Versions")
    Database.execute("DELETE FROM Encryption_Keys")
  end

  def load_api_token
    response = execute_post_request('login/do_logon', { email: "admin", password: MovexCdc::Application.config.db_password})
    assert_not_nil(response, "Response should not be nil")
    @api_token = response['token']
    assert_not_nil(@api_token, 'API token should not be nil')
  end

  # Add the default MOVEC CDC schema to config
  # @return
  def add_schema_to_config
    response = execute_post_request('schemas',
                                    {
                                      schema: {
                                        name: MovexCdc::Application.config.db_user,
                                        topic: 'TestTopic1',
                                      }
                                    }
    )
    assert_not_nil(response, "Response for schema should not be nil")
    response
  end

  def add_schema_rights_to_config(schema)
    user_id = Database.select_one "SELECT ID FROM users WHERE email = :email", email: 'admin'
    response = execute_post_request('schema_rights', {
      schema_right:{
        schema_id: schema['id'],
        user_id: user_id,
        yn_deployment_granted: 'Y'
      }})
    assert_not_nil(response, "Response for schema_right should not be nil")
    response
  end

  def add_table_to_config(table_data)
    response = execute_post_request('tables', { table: table_data })
    assert_not_nil(response, "Response for table should not be nil")
    response
  end

  # Call API with POST request
  # @param url [String] URL of the API
  # @param params [Hash] Parameters for the API
  # @return [Hash] Response from the API
  def execute_post_request(url, params)
    execute_api_request(request_class: Net::HTTP::Post, url: url, params: params)
  end

  # Call API with POST request
  # @param request_class [Class] Class of the request e.g. Net::HTTP::Post
  # @param url [String] URL of the API
  # @param headers [Hash] Header values
  # @param params [Hash] Parameters for the API
  # @return [Hash] Response from the API
  def execute_api_request(request_class:, url:, params:)
    uri = URI.parse("http://localhost:8080/#{url}")
    headers = {}
    headers['Authorization'] = @api_token if @api_token
    request = request_class.new(uri, headers)
    request.content_type = "application/json"
    request.body = JSON.dump(params)
    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end
    assert(response.code.to_i >= 200 && response.code.to_i < 300, "Request should be successful for #{url} with #{params}! Response body = #{response.body}")
    JSON.parse(response.body)
  end

end


