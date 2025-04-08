require 'test_helper'

class KafkaBaseTest < ActiveSupport::TestCase
  test "simple produce" do
    kafka = KafkaBase.create
    producer = kafka.create_producer(transactional_id: 'hugo2')
    producer.begin_transaction
    producer.produce(message: '{ "id": 1, "content": "Dummes zeug" }', table: victim1_table, key: nil, headers: {})
    producer.produce(message: '{ "id": 2, "content": "Dummes zeug 2" }', table: victim1_table, key: 'Hugo', headers: {Addition: 'Hugo'})
    producer.deliver_messages
    producer.commit_transaction
  rescue Exception => e
    log_on_failure("Exception #{e.class}: #{e.message}")
    producer&.abort_transaction
    raise
  ensure
    producer&.shutdown
  end

  test "topics" do
    kafka = KafkaBase.create
    topics = kafka.topics
    assert !topics.empty?, log_on_failure('topics should not be empty')

    assert kafka.has_topic?(victim1_table.topic_to_use), log_on_failure("Kafka should have topic #{victim1_table.topic_to_use}")
    assert !kafka.has_topic?('not_existing_topic'), log_on_failure("Kafka should not have that topic")
  end

  test "describe and alter topics" do
    kafka = KafkaBase.create
    org_max_message_bytes = kafka.describe_topic_attr(victim1_table.topic_to_use, 'max.message.bytes')
    org_retention_ms      = kafka.describe_topic_attr(victim1_table.topic_to_use, 'retention.ms')
    new_max_message_bytes = 10
    new_retention_ms      = 1000

    kafka.alter_topic(victim1_table.topic_to_use, { 'max.message.bytes' => new_max_message_bytes, 'retention.ms' => new_retention_ms })
    current_max_message_bytes = kafka.describe_topic_attr(victim1_table.topic_to_use, 'max.message.bytes')
    current_retention_ms      = kafka.describe_topic_attr(victim1_table.topic_to_use, 'retention.ms')
    assert current_max_message_bytes.to_i == new_max_message_bytes, log_on_failure("max.message.bytes should be #{new_max_message_bytes}, but is #{current_max_message_bytes}")
    assert current_retention_ms.to_i      == new_retention_ms,      log_on_failure("retention.ms should be #{new_retention_ms}, but is #{current_retention_ms}")

    # Reset original values
    kafka.alter_topic(victim1_table.topic_to_use, 'max.message.bytes' => org_max_message_bytes)
    kafka.alter_topic(victim1_table.topic_to_use, 'retention.ms'      => org_retention_ms)
  end

  test "describe_topic_complete" do
    kafka = KafkaBase.create
    description = kafka.describe_topic_complete(victim1_table.topic_to_use)
    assert !description.empty?, log_on_failure('topic description should not be empty')
    assert_equal Integer, description[:partitions].class,   log_on_failure('partitions should be an Integer')
    assert_equal Integer, description[:replicas].class,     log_on_failure('replicas should be an Integer')
    assert_equal Hash,    description[:last_offsets].class, log_on_failure('last_offsets should be an Hash')
    assert_equal Hash,    description[:leaders].class,      log_on_failure('leaders should be an Hash')
    assert_equal Hash,    description[:config].class,       log_on_failure('config should be an Hash')
  end

  test "groups" do
    kafka = KafkaBase.create
    groups = kafka.groups
    assert !groups.empty?, log_on_failure('groups should not be empty')

    assert groups.include?('Group1'), log_on_failure("Kafka should have a group named 'Group1'")
  end

  test "describe groups" do
    kafka = KafkaBase.create
    description = kafka.describe_group('Group1')
    assert !description.empty?, log_on_failure('group description should not be empty')
  end

  test "deliver_messages with MessageSizeTooLarge" do
    if MovexCdc::Application.config.kafka_client_library != 'mock'            # real Kafka connected
      kafka = KafkaBase.create
      org_max_message_bytes = kafka.describe_topic_attr(victim1_table.topic_to_use, 'max.message.bytes') # Save original value, value is of class String!
      begin
        kafka.alter_topic(victim1_table.topic_to_use, 'max.message.bytes' => '10')                         # Set a minimal value
        producer = kafka.create_producer(transactional_id: 'hugo14')
        producer.begin_transaction
        assert_raise do
          begin
            producer.produce(message: 'abcdefghijklm' * 11, table: victim1_table, key: nil, headers: {})
            producer.deliver_messages
            producer.commit_transaction
          ensure
            producer.abort_transaction
            producer.shutdown
          end
        end
        current_max_message_bytes = kafka.describe_topic_attr(victim1_table.topic_to_use, 'max.message.bytes').to_i
        assert(current_max_message_bytes > 10, log_on_failure("Should have increased max.message.bytes to more than 10 (#{current_max_message_bytes})"))
      ensure
        kafka.alter_topic(victim1_table.topic_to_use, 'max.message.bytes' => org_max_message_bytes)       # Restore original value
      end
    end
  end
end
