require 'test_helper'

class KafkaRubyTest < ActiveSupport::TestCase
  test "produce with Kafka::BufferOverflow" do
    if MovexCdc::Application.config.kafka_seed_broker != '/dev/null'            # real Kafka connected
      org_kafka_total_buffer_size_mb  = MovexCdc::Application.config.kafka_total_buffer_size_mb
      org_kafka_max_bulk_count        = MovexCdc::Application.config.kafka_max_bulk_count

      # Test with message size > 1/3 of kafka_total_buffer_size_mb, should not reduce kafka_max_bulk_count
      MovexCdc::Application.config.kafka_total_buffer_size_mb = 0.001  # 1 KB
      producer = KafkaBase.create.create_producer(transactional_id: 'hugo14')
      producer.begin_transaction
      assert_raise(Kafka::BufferOverflow) do
        1.upto(10) do |i|
          producer.produce(message: 'a' * 500, table: victim1_table, key: nil, headers: nil)
        end
      end
      assert(MovexCdc::Application.config.kafka_max_bulk_count == org_kafka_max_bulk_count, log_on_failure('kafka_max_bulk_count should not be changed'))

      # Test with message size < 1/3 of kafka_total_buffer_size_mb, should reduce kafka_max_bulk_count
      MovexCdc::Application.config.kafka_total_buffer_size_mb = 0.01  # 10 KB
      producer = KafkaBase.create.create_producer(transactional_id: 'hugo14')
      producer.begin_transaction
      assert_raise(Kafka::BufferOverflow) do
        1.upto(100) do |i|
          producer.produce(message: 'a' * 1000, table: victim1_table, key: nil, headers: nil)
        end
      end
      assert(MovexCdc::Application.config.kafka_max_bulk_count < org_kafka_max_bulk_count, log_on_failure('kafka_max_bulk_count should be reduced'))
      #producer.abort_transaction

      # Restore original values at end of test
      MovexCdc::Application.config.kafka_total_buffer_size_mb = org_kafka_total_buffer_size_mb
      MovexCdc::Application.config.kafka_max_bulk_count       = org_kafka_max_bulk_count
    end
  end

  test "deliver_messages with Kafka::MessageSizeTooLarge" do
    if MovexCdc::Application.config.kafka_seed_broker != '/dev/null'            # real Kafka connected
      kafka = KafkaBase.create
      kafka.alter_topic(victim1_table.topic_to_use, 'max.message.bytes' => '10')                         # Set a minimal value
      producer = kafka.create_producer(transactional_id: 'hugo13')
      producer.begin_transaction
      producer.produce(message: 'a' * 11, table: victim1_table, key: nil, headers: nil)
      assert_raise(Kafka::MessageSizeTooLarge) { producer.deliver_messages }
      producer.abort_transaction
      assert(kafka.describe_topic(KafkaHelper.existing_topic_for_test, ['max.message.bytes'])['max.message.bytes'].to_i > 10, log_on_failure('Should have increased max.message.bytes'))
    end
  end
end
