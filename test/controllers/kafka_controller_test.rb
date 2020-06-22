require 'test_helper'

class KafkaControllerTest < ActionDispatch::IntegrationTest
  test "should get topics" do
    get "/kafka/topics", as: :json
    assert_response :unauthorized, 'No access without JWT'

    get "/kafka/topics", headers: jwt_header, as: :json
    assert_response :success, 'should get topics with JWT'
  end

  test "should get describe_topic" do
    get "/kafka/describe_topic", as: :json
    assert_response :unauthorized, 'No access without JWT'

    get "/kafka/topics", headers: jwt_header, as: :json
    topic = eval(response.body)[:topics][0]

    get "/kafka/describe_topic?topic=#{topic}", headers: jwt_header, as: :json
    assert_response :success, 'should get topic description with JWT'
  end

end