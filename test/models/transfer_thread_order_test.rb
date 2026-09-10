require 'test_helper'

# Ensure that TransferThread transfers the events to Kafka in the order of their creation (Event_Logs.ID).
# This order is relevant for events with a Kafka message key: Kafka guarantees the consumption order only
# within a partition of a topic and messages with the same key are stored in the same partition.
# Therefore the order in which MOVEX CDC hands over the messages to Kafka has to be identical
# to the ascending order of Event_Logs.ID for each message key.
class TransferThreadOrderTest < ActiveSupport::TestCase

  # Records the messages that really have been committed to Kafka in the order of production.
  # Recording is hooked into the used Kafka producer implementation, therefore the test works
  # for KAFKA_CLIENT_LIBRARY = 'mock' as well as for 'java'.
  # Only messages of committed Kafka transactions are recorded because only these are visible
  # for a consumer reading with isolation.level = read_committed.
  module ProducedMessageRecorder
    @mutex     = Mutex.new
    @recording = false
    @committed = []                                                             # messages of committed transactions in order of production
    @pending   = {}                                                             # messages of the current transaction per producer

    class << self
      # Start a new recording, records of a previous recording are discarded
      # @return [void]
      def start
        @mutex.synchronize do
          @committed = []
          @pending   = {}
          @recording = true
        end
      end

      # @return [void]
      def stop
        @mutex.synchronize { @recording = false }
      end

      # @return [Array<Hash>] the committed messages in the order of production ( { key:, id: } )
      def committed
        @mutex.synchronize { @committed.clone }
      end

      # Remember a message produced within the current Kafka transaction of a producer
      # @param producer [KafkaBase::Producer] the producer that produced the message
      # @param key [String, nil] the Kafka message key of the message
      # @param message [String] the produced message
      # @return [void]
      def produced(producer, key, message)
        return unless @recording
        @mutex.synchronize do
          @pending[producer.object_id] = [] unless @pending.has_key?(producer.object_id)
          @pending[producer.object_id] << { key: key, id: JSON.parse(message)['id'].to_i }
        end
      end

      # Move the messages of the committed transaction to the recorded result
      # @param producer [KafkaBase::Producer] the producer that committed the transaction
      # @return [void]
      def commit(producer)
        @mutex.synchronize { @committed.concat(@pending.delete(producer.object_id) || []) }
      end

      # Drop the messages of a not committed transaction, they are not visible for consumers
      # @param producer [KafkaBase::Producer] the producer that aborted or restarted the transaction
      # @return [void]
      def discard(producer)
        @mutex.synchronize { @pending.delete(producer.object_id) }
      end
    end
  end

  # Prepended to the used implementation of KafkaBase::Producer to feed the ProducedMessageRecorder
  module ProducerHook
    def produce(message:, table:, key: nil, headers: {})
      result = super(message: message, table: table, key: key, headers: headers)
      ProducedMessageRecorder.produced(self, key, message)                      # record only if produce did not raise an exception
      result
    end

    def begin_transaction
      ProducedMessageRecorder.discard(self)                                     # drop possible remains of a previous transaction
      super
    end

    def commit_transaction
      result = super
      ProducedMessageRecorder.commit(self)                                      # only a committed transaction is visible for consumers
      result
    end

    def abort_transaction
      ProducedMessageRecorder.discard(self)
      super
    end
  end

  setup do
    create_victim_structures
    producer_class = case MovexCdc::Application.config.kafka_client_library
                     when 'java' then KafkaJava::Producer
                     when 'mock' then KafkaMock::Producer
                     else raise "Unsupported value '#{MovexCdc::Application.config.kafka_client_library}' for KAFKA_CLIENT_LIBRARY"
                     end
    producer_class.prepend(ProducerHook) unless producer_class.ancestors.include?(ProducerHook)
  end

  test "events with the same message key are transferred to Kafka in ascending ID order" do
    # All events of both victim tables share one single message key, therefore the order of production
    # has to be exactly the ascending order of Event_Logs.ID
    with_key_handling(victim1_table.id => { kafka_key_handling: 'F', fixed_message_key: 'ORDER_TEST' },
                      victim2_table.id => { kafka_key_handling: 'F', fixed_message_key: 'ORDER_TEST' }) do
      created_ids, produced = transfer_and_record(number_of_events:     40,
                                                  max_transaction_size: 5,
                                                  title:                'Single message key for all events'
                              )

      assert_equal 1, produced_ids_per_key(produced).count, log_on_failure("All events should be produced with the same message key but are: #{produced_ids_per_key(produced).keys}")
      assert_ascending_ids_per_key(produced)
      assert_equal created_ids, produced.map { |p| p[:id] }, log_on_failure('All events should be produced exactly once in the ascending order of their ID')
    end
  end

  test "events with and without message key keep the ID order per key" do
    # Events with key (VICTIM1) and without key (VICTIM2) are mixed in Event_Logs, so all three read steps
    # of read_event_logs_steps are used to fill the batches. The events without key may be produced in any
    # order (Kafka uses random partitions for them), the events with key must not be reordered.
    with_key_handling(victim1_table.id => { kafka_key_handling: 'F', fixed_message_key: 'VICTIM1_KEY' },
                      victim2_table.id => { kafka_key_handling: 'N' }) do
      created_ids, produced = transfer_and_record(number_of_events:     40,
                                                  max_transaction_size: 5,
                                                  title:                'Mixed events with and without message key'
                              )

      ids_per_key = produced_ids_per_key(produced)
      assert ids_per_key.has_key?('VICTIM1_KEY'), log_on_failure("Events with message key are needed for this test but produced keys are: #{ids_per_key.keys}")
      assert ids_per_key.has_key?(nil),           log_on_failure("Events without message key are needed for this test but produced keys are: #{ids_per_key.keys}")
      assert_ascending_ids_per_key(produced)
      assert_equal created_ids, produced.map { |p| p[:id] }.sort, log_on_failure('All events should be produced exactly once')
    end
  end

  private

  # Execute the block with the given Kafka key handling for tables and restore the previous config afterwards
  # @param table_configs [Hash] attributes to set per table ID ( { table_id => { kafka_key_handling:, fixed_message_key: } } )
  # @return [void]
  def with_key_handling(table_configs)
    original_configs = table_configs.keys.map { |table_id| [table_id, Table.find(table_id).slice(:kafka_key_handling, :fixed_message_key)] }.to_h
    run_with_current_user do
      table_configs.each { |table_id, config| Table.find(table_id).update!(config) }
    end
    yield
  ensure
    run_with_current_user do                                                    # triggers are regenerated by the next test creating events
      original_configs.each { |table_id, config| Table.find(table_id).update!(config) }
    end
  end

  # Create events by trigger, transfer them to Kafka and record the order of production
  # @param number_of_events [Integer] number of events to create in Event_Logs
  # @param max_transaction_size [Integer] max. number of events processed by the worker at once.
  #        A value much smaller than number_of_events ensures that
  #        - multiple batches are needed, so the order has to be kept also between the batches
  #        - the adaptive ID window of read_keyed_events has to be reduced (SortedIdWindow.shrink_to_fit / get_min_key_id)
  # @param title [String] title for the log output
  # @return [Array(Array, Array)] the created Event_Logs IDs in ascending order and the recorded messages in order of production
  def transfer_and_record(number_of_events:, max_transaction_size:, title:)
    Database.execute "DELETE FROM Event_Logs"                                   # ensure the recorded messages are exactly the events created here
    Database.execute "DELETE FROM Event_Log_Final_Errors"
    run_with_current_user { create_event_logs_for_test(number_of_events) }
    created_ids = Database.select_all("SELECT ID FROM Event_Logs ORDER BY ID").map { |e| e['id'].to_i }

    begin
      ProducedMessageRecorder.start
      remaining_event_log_count = process_eventlogs(max_wait_time:              60,
                                                    expected_remaining_records: 0,
                                                    max_transaction_size:       max_transaction_size,
                                                    title:                      title
                                  )
    ensure
      ProducedMessageRecorder.stop
    end

    assert_equal 0, remaining_event_log_count, log_on_failure("#{title}: All events should be transferred to Kafka and deleted from Event_Logs")
    assert_equal number_of_events, created_ids.count, log_on_failure("#{title}: Exactly #{number_of_events} events should have been created")
    [created_ids, ProducedMessageRecorder.committed]
  end

  # @param produced [Array<Hash>] the recorded messages in the order of production
  # @return [Hash] the produced Event_Logs IDs in order of production per message key
  def produced_ids_per_key(produced)
    result = {}
    produced.each do |message|
      result[message[:key]] = [] unless result.has_key?(message[:key])
      result[message[:key]] << message[:id]
    end
    result
  end

  # Ensure that the events of each message key are produced exactly once in ascending ID order
  # @param produced [Array<Hash>] the recorded messages in the order of production
  # @return [void]
  def assert_ascending_ids_per_key(produced)
    assert produced.count > 0, log_on_failure('Messages should have been produced to Kafka')
    produced_ids_per_key(produced).each do |key, ids|
      next if key.nil?                                                          # events without key are placed in random partitions, so their order is not relevant
      assert_equal ids.uniq, ids,  log_on_failure("Events with message key '#{key}' should be produced exactly once but are produced in this order: #{ids}")
      assert_equal ids.sort, ids,  log_on_failure("Events with message key '#{key}' should be produced in ascending ID order but are produced in this order: #{ids}")
    end
  end
end
