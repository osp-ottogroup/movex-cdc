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

    get "/kafka/describe_topic?topic=#{KafkaHelper.existing_topic_for_test}", headers: jwt_header, as: :json
    assert_response :success, 'should get topic description with JWT'
  end

  test "should get has_topic" do
    get "/kafka/has_topic", as: :json
    assert_response :unauthorized, 'No access without JWT'

    get "/kafka/has_topic?topic=#{KafkaHelper.existing_topic_for_test}", headers: jwt_header, as: :json
    assert_response :success, 'get existing topic with JWT'
    assert_equal eval(response.body)[:has_topic], true, "Topic #{KafkaHelper.existing_topic_for_test} should exist"

    get "/kafka/has_topic?topic=NotExisting", headers: jwt_header, as: :json
    assert_response :success, 'get not existing topic with JWT'
    assert_equal eval(response.body)[:has_topic], false, "Topic should not exist"

  end

  test "should get groups" do
    get "/kafka/groups", as: :json
    assert_response :unauthorized, 'No access without JWT'

    get "/kafka/groups", headers: jwt_header, as: :json
    assert_response :success, 'should get groups with JWT'
  end

  test "should describe group" do
    get "/kafka/describe_group", as: :json
    assert_response :unauthorized, 'No access without JWT'

    get "/kafka/describe_group?group_id=#{KafkaHelper.existing_group_id_for_test}", headers: jwt_header, as: :json
    assert_response :success, 'should get group description with JWT'
  end

end