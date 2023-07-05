# Implementation for Kafka producer functions using the Java client libs

require 'java'


# make Kafka libs available
kafka_lib_dir = File.expand_path('../../../lib/kafka', __FILE__)
# set log4j configuration for Kafka libs
java.lang.System.setProperty('log4j.configurationFile', kafka_lib_dir + '/log4j.properties')

Dir.glob(kafka_lib_dir+'/*.jar').each do |jar|
  require jar
end

# builder = org.apache.logging.log4j.core.config.builder.api.ConfigurationBuilderFactory.newConfigurationBuilder
class KafkaJava < KafkaBase
  class Producer < KafkaBase::Producer

    # Create producer instance
    # @param [KafkaRuby] kafka Instance of KafkaRuby
    # @param [String] transactional_id Transactional id for the producer
    # @return [void]
    def initialize(kafka, transactional_id:)
      super(kafka, transactional_id: transactional_id)
      @kafka_producer             = nil
      @topic_infos                = {}                                          # Max message size produced so far per topic
      create_kafka_producer
    end

    def begin_transaction
      @kafka_producer&.beginTransaction
    end

    def commit_transaction
      @kafka_producer&.commitTransaction
    rescue Exception => e
      if e.class == Java::OrgApacheKafkaCommonErrors::RecordTooLargeException
        Rails.logger.warn('KafkaJava::Producer.commit_transaction') { "#{e.class} #{e.message}: max_message_size = #{@max_message_size}, max_buffer_size = #{max_message_bulk_count}, max_buffer_bytesize = #{@max_buffer_bytesize}" }
        fix_message_size_too_large
      end
      if e.class == Kafka::ConcurrentTransactionError
        raise KafkaBase::ConcurrentTransactionError.new(e.message)                # Use generic error class to avoid dependency on Ruby-Kafka gem
      end
      raise
    end

    def abort_transaction
      @kafka_producer&.abortTransaction
    end

    # remove all pending (not processed by kafka) messages from producer buffer
    # Nothing to do yet for Java producer
    # @return [void]
    def clear_buffer
    end


    # Create a single Kafka message
    # @param [String] message Message to send
    # @param [Table] table Table object of the message
    # @param [String] key Key of the message, may be nil
    # @param [Hash] headers Headers of the message, may not be nil
    # @return [void]
    def produce(message:, table:, key:, headers: )
      topic = table.topic_to_use
      record = key.nil? ?
                 org.apache.kafka.clients.producer.ProducerRecord.new(topic, message) :
                 org.apache.kafka.clients.producer.ProducerRecord.new(topic, key, message)
      headers.each do | hkey, hvalue|
        record.headers.add(org.apache.kafka.clients.producer.RecordHeader.new(hkey, hvalue))
      end

      @kafka_producer.send(record)                                              # Send message to Kafka

      @topic_infos[topic] = { max_produced_message_size: message.bytesize } if !@topic_infos.has_key?(topic) || message.bytesize > @topic_infos[topic][:max_produced_message_size]
    rescue Kafka::BufferOverflow => e
      handle_kafka_buffer_overflow(e, message, topic, table)
      raise                                                               # Ensure transaction is rolled back an retried
    rescue Kafka::MessageSizeTooLarge => e
      Rails.logger.warn('KafkaRuby::Producer.produce') { "#{e.class} #{e.message}: max_message_size = #{@max_message_size}, max_buffer_size = #{max_message_bulk_count}, max_buffer_bytesize = #{@max_buffer_bytesize}" }
      fix_message_size_too_large
      raise
    rescue Kafka::ConcurrentTransactionError => e
      raise KafkaBase::ConcurrentTransactionError.new(e.message)                # Use generic error class to avoid dependency on Ruby-Kafka gem
    rescue Exception => e
      Rails.logger.error('KafkaJava::Producer.produce') { "#{e.class} #{e.message} max_message_size = #{@max_message_size}, max_buffer_size = #{max_message_bulk_count}, max_buffer_bytesize = #{@max_buffer_bytesize}" }
      raise
    end

    # send a batch of messages cumulated by produce() to Kafka
    # This method is not needed for KafkaJava, but is required for KafkaRuby
    # @return [void]
    def deliver_messages
    end

    # Cancel previous producer and recreate again

    def reset_kafka_producer
      @kafka_producer&.close                                                    # free kafka connections of current producer if != nil
      create_kafka_producer                                                     # get fresh producer
    end

    def shutdown
      Rails.logger.info('KafkaJava::Producer,shutdown') { "Shutdown the Kafka producer" }
      @kafka_producer&.close                                                    # free kafka connections if != nil
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
          producer_properties =@kafka.connect_properties
          producer_properties.put('transactional.id',     @transactional_id)
          producer_properties.put('enable.idempotence',   'true')               # required if using transactional.id
          producer_properties.put('key.serializer',       'org.apache.kafka.common.serialization.StringSerializer') # According to predecessor ruby-kafka
          producer_properties.put('value.serializer',     'org.apache.kafka.common.serialization.StringSerializer') # According to predecessor ruby-kafka
          # producer_properties.put('retries',              java.lang.Integer.new(0))  # ensure producer does not sleep between retries, setting > 0 will reduce MOVEX CDC's throughput
          # producer_properties.put('delivery.timeout.ms',  100) # Possible way to reduce the time for retries, if retries > 0
          producer_properties.put('linger.ms',              java.lang.Integer.new(10))  # Number of m to wait for more messages before sending a batch
          # TODO: create config entry for linger.ms or adjust dynamically
          # producer_properties.put('batch.size',           @max_buffer_bytesize)  # maximum size of a batch of messages to send in bytes. Allocated per partition!!!
          # TODO: adjust KAFKA_TOTAL_BUFFER_SIZE_MB to including the number of threads and document the multiplication with max. partition count
          # TODO: Add test where the buffer excceeds the OS limits and exception handler decreases this value
          # TODO: Check if config KAFKA_MAX_BULK_COUNT (@max_message_bulk_count) can be further used
          producer_properties.put('buffer.memory',          @max_buffer_bytesize)  # maximum size of memory for buffering messages to send in bytes
          # TODO: Check if buffer.memory with transactions leads to batching or if batch.size hast to be set in addition
          producer_properties.put('acks',                   'all')              # The default for enabled itempotence which is enabled by transactional
          producer_properties.put('compression.codec',      MovexCdc::Application.config.kafka_compression_codec) if MovexCdc::Application.config.kafka_compression_codec != 'none'

          Rails.logger.debug('KafkaJava::Producer.create_kafka_producer'){"creating Kafka producer with options: #{producer_properties}"}
          @kafka_producer = org.apache.kafka.clients.producer.KafkaProducer.new(producer_properties)

          Rails.logger.debug('KafkaJava::Producer.create_kafka_producer'){"calling kafka_producer.init_transactions"}
          @kafka_producer.init_transactions                                        # Should be called once before starting transactions
          init_transactions_successfull = true                                    # no exception raise
        rescue Exception => e
          @kafka_producer&.close                                                # clear existing producer
          ExceptionHelper.log_exception(e, 'KafkaJava.create_kafka_producer', additional_msg: "Producer properties = #{producer_properties}\nRetry count = #{init_transactions_retry_count}")
          if init_transactions_retry_count < MAX_INIT_TRANSACTION_RETRY
            sleep 1
            init_transactions_retry_count += 1
            if e.class == Java::OrgApacheKafkaCommonErrors::TimeoutException # change transactional_id as workaround for Kafka::ConcurrentTransactionError
              @transactional_id << '-'
              Rails.logger.warn('KafkaJava::Producer.create_kafka_producer'){"KafkaException catched (#{e.message}). Retry #{init_transactions_retry_count} with new transactional_id = #{@transactional_id}. Possible reason: missing abort_transaction before reuse of transactional_id" }
            end
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
    @producer = nil                                                             # KafkaRuby::Producer is not initialized until needed
  end

  public

  # @return [Array] List of Kafka topic names
  def topics
    run_with_admin do |admin|
      topics = admin.listTopics # returns a Java::OrgApacheKafkaClientsAdmin::ListTopicsResult
      topics.names.get.to_a.sort
    end
  end

  # @param topic [String] Kafka topic name to check for existence
  # @return [Boolean] True if the topic exists
  def has_topic?(topic)
    topics.include?(topic)
  end

  # Describe a single Kafka topic attribute
  # @param topic [String] Kafka topic name to describe
  # @param attribute [String] Kafka topic attribute to describe
  # @return [String] Value of the Kafka topic attribute
  def describe_topic_attr(topic, attribute)
    attributes = describe_all_topic_attrs(topic)                                # get all attributes of the topic
    if attributes.has_key?(attribute)
      attributes[attribute][:value]
    else
      nil
    end
  end

  # @param topic [String] Kafka topic name to describe with all attributes
  # @return [Hash] Description of the Kafka topic { partitions: 3, replicas: 2, last_offsets: {}, leaders: {}, config: {} }
  def describe_topic_complete(topic)
    result = {}
    run_with_admin do |admin|
      description = admin.describeTopics([topic]).all.get[topic]
      raise "Description for topic '#{topic}' not found at Kafka" if description.nil?
      result[:partitions]   = description.partitions.count
      result[:replicas]     = description.partitions.first.replicas.count       # all partitions have the same number of replicas
      result[:last_offsets] = {}
      result[:leaders]      = {}
      offset_specs = {}
      description.partitions.each do |partition|
        result[:leaders][partition.partition.to_s]      = partition.leader.to_s
        # get the last offsets of the partitions
        topic_partition = org.apache.kafka.common.TopicPartition.new(topic, partition.partition)
        offset_specs[topic_partition] = org.apache.kafka.clients.admin.OffsetSpec.latest
      end
      list_offsets_result = admin.listOffsets(offset_specs)
      list_offsets_result.all.get.each do |topic_partition, offset_and_metadata|
        result[:last_offsets][topic_partition.partition.to_s] = offset_and_metadata.offset
      end
    end
    begin                                                                       # get the topic configuration without attributes if access is denied
      result[:config] = describe_all_topic_attrs(topic)
    rescue Exception => e
      result[:config] = "Exception: #{e.class}:#{e.message}"
    end
    result
  end

  # Change topic settings
  # @param topic [String] Kafka topic name to change
  # @param settings [Hash] Settings to change
  def  alter_topic(topic, settings)
    run_with_admin do |admin|
      topicResource = org.apache.kafka.common.config.ConfigResource.new(org.apache.kafka.common.config.ConfigResource::Type::TOPIC, topic)
      alter_config_ops = []
      settings.each do |key, value|
        configEntry = org.apache.kafka.clients.admin.ConfigEntry.new(key, value.to_s) # Ensure properties are written as strings
        alter_config_ops << org.apache.kafka.clients.admin.AlterConfigOp.new(configEntry, org.apache.kafka.clients.admin.AlterConfigOp::OpType::SET)
      end
      alterConfigsResult = admin.incrementalAlterConfigs(java.util.Collections.singletonMap(topicResource, alter_config_ops))
      alterConfigsResult.all().get()  # Raise exception if incrementalAlterConfigs failed
    end
  end

  # @return [Array] List of Kafka group names
  def groups
    run_with_admin do |admin|
      groups = admin.listConsumerGroups # returns a Java::OrgApacheKafkaClientsAdmin::ListTopicsResult
      groups.all.get.to_a.map{|g| g.groupId}.sort
    end
  end

  # Get the description of a Kafka group (consumer group)
  # @param group_id [Integer] Kafka group id
  # @return [Hash] Description of the Kafka group
  def describe_group(group_id)
    run_with_admin do |admin|
      describe_consumer_groups_result = admin.describeConsumerGroups([group_id.to_s])
      group_description = describe_consumer_groups_result.describedGroups.get(group_id.to_s).get
      # return attributes of org.apache.kafka.clients.admin.ConsumerGroupDescription  as a hash
      {
        groupId:                group_description.groupId,
        isSimpleConsumerGroup:  group_description.isSimpleConsumerGroup,
        members:                group_description.members,
        partitionAssignor:      group_description.partitionAssignor,
        state:                  group_description.state,
        coordinator:            group_description.coordinator,
        authorizedOperations:   group_description.authorizedOperations
      }
    end
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

  # Basic Kafka options for connection to cluster including SSL options
  # @return [java.util.Properties] Basic Kafka options for connection to cluster
  def connect_properties
    props = java.util.Properties.new
    props.put('bootstrap.servers',  config[:seed_brokers])

=begin
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
=end

    props
  end

  private
  # Create instance of org.apache.kafka.clients.admin.Admin for onetime use
  def run_with_admin
    admin = org.apache.kafka.clients.admin.Admin.create(connect_properties)
    result = yield admin
    admin.close
    result
  end

  # Get all attributes for a topic, enriched with info from KafkaBase
  # @return [Hash] Kafka topic attributes for describe { name: { value:, info:}}
  def describe_all_topic_attrs(topic)
    result = {}
    run_with_admin do |admin|
      topicResource = org.apache.kafka.common.config.ConfigResource.new(org.apache.kafka.common.config.ConfigResource::Type::TOPIC, topic)
      describeConfigsResult = admin.describeConfigs([topicResource])
      attribute_info = topic_attributes_for_describe                            # info from KafkaBase, cloned only once
      config_list = describeConfigsResult.all().get().get(topicResource).entries.to_a.each do |entry|
        # entry = org.apache.kafka.clients.admin.ConfigEntry(name=compression.type, value=producer, source=DEFAULT_CONFIG, isSensitive=false, isReadOnly=false, synonyms=[], type=STRING, documentation=null)
        result[entry.name] = { value: entry.value, info: attribute_info[entry.name][:info] }
      end
      result.sort.to_h                                                          # sort by key
    end
  end
end