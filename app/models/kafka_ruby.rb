# Implementation for Kafka producer functions using Ruby-Kafka gem
class KafkaRuby < KafkaBase
  attr_reader :internal_kafka
  class Producer < KafkaBase::Producer

    # Create producer instance
    # @param [KafkaRuby] kafka Instance of KafkaRuby
    # @param [String] transactional_id Transactional id for the producer
    # @return [void]
    def initialize(kafka, transactional_id:)
      super(kafka, transactional_id: transactional_id)
      @kafka_producer             = nil
      create_kafka_producer
    end

    def begin_transaction
      @kafka_producer&.begin_transaction
      @topic_infos.clear                                                        # Clear topic_infos to get new max_produced_message_size
    end

    def commit_transaction
      @kafka_producer&.commit_transaction
    end

    def abort_transaction
      @kafka_producer&.abort_transaction
    end

    # remove all pending (not processed by kafka) messages from producer buffer
    # @return [void]
    def clear_buffer
      @kafka_producer&.clear_buffer
    end


    # Create a single Kafka message
    # @param [String] message Message to send
    # @param [Table] table Table object of the message
    # @param [String] key Key of the message
    # @param [Hash] headers Headers of the message
    def produce(message:, table:, key: nil, headers: {})
      topic = table.topic_to_use
      # Store messages in local collection, Kafka::BufferOverflow exception is handled by divide&conquer
      @kafka_producer.produce(message, topic: topic, key: key, headers: headers)
      @topic_infos[topic] = { max_produced_message_size: message.bytesize } if !@topic_infos.has_key?(topic) || message.bytesize > @topic_infos[topic][:max_produced_message_size]
    rescue Kafka::BufferOverflow => e
      handle_kafka_buffer_overflow(e, message, topic, table)
      raise                                                               # Ensure transaction is rolled back an retried
    end

    def deliver_messages
      @kafka_producer.deliver_messages
    rescue Kafka::MessageSizeTooLarge => e
      Rails.logger.warn('KafkaRuby::Producer.deliver_Messages') { "#{e.class} #{e.message}: max_buffer_size = #{max_message_bulk_count}, max_buffer_bytesize = #{@max_buffer_bytesize}" }
      fix_message_size_too_large
      raise
    rescue Kafka::ConcurrentTransactionError => e
      raise KafkaBase::ConcurrentTransactionError.new(e.message)                # Use generic error class to avoid dependency on Ruby-Kafka gem
    end

    # Cancel previous producer and recreate again

    def reset_kafka_producer
      @kafka_producer&.shutdown                                                 # free kafka connections of current producer if != nil
      create_kafka_producer                                                     # get fresh producer
    end

    def shutdown
      Rails.logger.info('KafkaRuby::Producer,shutdown') { "Shutdown the Kafka producer" }
      @kafka_producer&.shutdown                                                 # free kafka connections if != nil
    end

    private
    MAX_INIT_TRANSACTION_RETRY=3
    # create the instance of Kafka producer
    # @return [void]
    def create_kafka_producer
      init_transactions_successfull = false
      init_transactions_retry_count = 0

      while !init_transactions_successfull

        begin
          producer_options = {
            max_buffer_size:      @max_message_bulk_count,
            max_buffer_bytesize:  @max_buffer_bytesize,
            transactional_id:     @transactional_id,
            transactional:        true,
            max_retries: 0                                                      # ensure producer does not sleep between retries, setting > 0 will reduce MOVEX CDC's throughput
          }

          producer_options[:compression_codec]             = MovexCdc::Application.config.kafka_compression_codec.to_sym        if MovexCdc::Application.config.kafka_compression_codec != 'none'

          Rails.logger.debug('KafkaRuby::Producer.create_kafka_producer'){"creating Kafka producer with options: #{producer_options}"}
          # **producer_options instead of producer_options needed for compatibility with jRuby 9.4.0.0, possibly due to a bug
          @kafka_producer = @kafka.internal_kafka.producer(**producer_options)

          Rails.logger.debug('KafkaRuby::Producer.create_kafka_producer'){"calling kafka_producer.init_transactions"}
          @kafka_producer.init_transactions                                        # Should be called once before starting transactions
          init_transactions_successfull = true                                    # no exception raise
        rescue Exception => e
          @kafka_producer&.shutdown                                                # clear existing producer
          ExceptionHelper.log_exception(e, 'KafkaRuby.create_kafka_producer', additional_msg: "Producer options = #{producer_options}\nRetry count = #{init_transactions_retry_count}")
          if init_transactions_retry_count < MAX_INIT_TRANSACTION_RETRY
            sleep 1
            init_transactions_retry_count += 1
            producer_options[:transactional_id] << '-' if e.class == Kafka::ConcurrentTransactionError # change transactional_id as workaround for Kafka::ConcurrentTransactionError
          else
            raise
          end
        end
      end
    end
  end # class Producer

  private
  # Use KafkaBase.create to create an instance of this class
  def initialize
    super
    kafka_options = {
      client_id:                    config[:client_id],
      logger:                       Rails.logger,
      ssl_ca_certs_from_system:     config[:ssl_ca_certs_from_system],
      ssl_ca_cert_file_path:        config[:ssl_ca_cert_file_path],
      ssl_client_cert_chain:        config[:ssl_client_cert_chain],
      ssl_client_cert:              config[:ssl_client_cert],
      ssl_client_cert_key:          config[:ssl_client_cert_key],
      ssl_client_cert_key_password: config[:ssl_client_cert_key_password],
      sasl_plain_username:          config[:sasl_plain_username],
      sasl_plain_password:          config[:sasl_plain_password]
    }

    # **kafka_options instead of kafka_options needed for compatibility with jRuby 9.4.0.0, possibly due to a bug
    @internal_kafka = Kafka.new(config[:seed_brokers], **kafka_options)                  # return instance of Kafka
    @producer = nil                                                             # KafkaRuby::Producer is not initialized until needed
  end

  public

  # @return [Array] List of Kafka topic names
  def topics
    @internal_kafka.topics.sort
  end

  # Describe a single Kafka topic attribute
  # @param topic [String] Kafka topic name to describe
  # @param attribute [String] Kafka topic attribute to describe
  # @return [String] Value of the Kafka topic attribute
  def describe_topic_attr(topic, attribute)
    @internal_kafka.describe_topic(topic, [attribute])[attribute]
  end

  # @param topic [String] Kafka topic name to describe with all attributes
  # @return [Hash] Description of the Kafka topic
  def describe_topic_complete(topic)
    cluster = @internal_kafka.instance_variable_get('@cluster')                           # possibly instable access on internal structures
    result = {}

    result[:partitions]   = @internal_kafka.partitions_for(topic)
    result[:replicas]     = @internal_kafka.replica_count_for(topic)
    result[:last_offsets] = @internal_kafka.last_offsets_for(topic)[topic]
    result[:leaders]      = {}
    0.upto(result[:partitions]-1) do |p|
      result[:leaders][p.to_s] = cluster.get_leader(topic, p).to_s
    rescue Exception => e
      result[:leaders][p.to_s] = "Exception: #{e.class}:#{e.message}"
    end
    begin
      config_values = @internal_kafka.describe_topic(topic, topic_attributes_for_describe.map{|key, _value| key})
      result_config = topic_attributes_for_describe
      config_values.each do |key, value|
        result_config[key][:value] = value
      end
      result[:config] = result_config
    rescue Exception => e
      result[:config] = "Exception: #{e.class}:#{e.message}"
    end
    result
  end

  # Change topic settings
  # @param topic [String] Kafka topic name to change
  # @param settings [Hash] Settings to change
  def  alter_topic(topic, settings)
    @internal_kafka.alter_topic(topic, settings)
  end

  # Create a new Kafka topic
  # @param topic [String] Kafka topic name to create
  # @return [void]
  def create_topic(topic)
    @internal_kafka.create_topic(topic)
  end

  # @return [Array] List of Kafka group names
  def groups
    @internal_kafka.groups
  end

  # Get the description of a Kafka group (consumer group)
  # @param group_id [Integer] Kafka group id
  # @return [Hash] Description of the Kafka group
  def describe_group(group_id)
    # Kafka::Protocol::DescribeGroupsResponse::Group can be transformed to JSON by to_json
    JSON.parse(@internal_kafka.describe_group(group_id).to_json)
  end

  # Create instance of KafkaRuby::Producer
  # @param transactional_id [String] Transactional id for the producer
  # @return [KafkaRuby::Producer] Instance of KafkaRuby::Producer
  def create_producer(transactional_id:)
    if @producer.nil?
      @producer = Producer.new(self, transactional_id: transactional_id)
    else
      raise "KafkaRuby::create_producer: producer already initialized! Only one producer per instance allowed."
    end
    @producer
  end

  # @return [KafkaRuby::Producer] Instance of KafkaRuby::Producer if exists
  def producer
    if @producer.nil?
      raise "KafkaRuby::producer: producer not yet created! Call KafkaRuby::create_producer(options) first."
    else
      @producer
    end
  end

end