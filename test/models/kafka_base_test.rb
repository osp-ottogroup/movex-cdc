require 'test_helper'

class KafkaBaseTest < ActiveSupport::TestCase
  test "deliver_messages with Kafka::MessageSizeTooLarge" do
    if MovexCdc::Application.config.kafka_seed_broker != '/dev/null'            # real Kafka connected
      kafka = KafkaBase.create
      org_max_message_bytes = kafka.describe_topic_attr(victim1_table.topic_to_use, 'max.message.bytes') # Save original value, value is of class String!
      kafka.alter_topic(victim1_table.topic_to_use, 'max.message.bytes' => '10')                         # Set a minimal value
      producer = kafka.create_producer(transactional_id: 'hugo13')
      producer.begin_transaction
      producer.produce(message: 'abcdefghijklm' * 11, table: victim1_table, key: nil, headers: nil)
      assert_raise(Kafka::MessageSizeTooLarge) { producer.deliver_messages }
      producer.abort_transaction
      assert(kafka.describe_topic_attr(KafkaHelper.existing_topic_for_test, 'max.message.bytes').to_i > 10, log_on_failure('Should have increased max.message.bytes'))
      kafka.alter_topic(victim1_table.topic_to_use, 'max.message.bytes' => org_max_message_bytes)       # Restore original value
    end
  end
end
