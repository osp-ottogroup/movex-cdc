# Implementation for Kafka producer functions using the Java client libs

require 'java'
require 'java-properties'


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
      @pending_transaction       = nil                                          # Is there a pending transaction? nil or timestamp
      @kafka_producer            = nil
      create_kafka_producer
    end

    def begin_transaction
      Rails.logger.error('KafkaJava::Producer.begin_transaction') { "There is already a pending_transaction since #{@pending_transaction}" } unless @pending_transaction.nil?
      Rails.logger.debug('KafkaJava::Producer.begin_transaction') { "Starting transaction" }
      @kafka_producer&.beginTransaction
      @pending_transaction = Time.now                                           # Mark transaction as active/pending by setting timestamp
      @topic_infos.clear                                                        # Clear topic_infos to get new max_produced_message_size
    end

    def commit_transaction
      Rails.logger.error('KafkaJava::Producer.commit_transaction') { "There is no pending_transaction" } if @pending_transaction.nil?
      Rails.logger.debug('KafkaJava::Producer.commit_transaction') { "Committing transaction" }
      @kafka_producer&.commitTransaction
      @pending_transaction = nil                                                # Mark transaction as inactive by setting to nil
    rescue Exception => e
      Rails.logger.error('KafkaJava::Producer.commit_transaction') { "#{e.class} #{e.message} max_buffer_size = #{max_message_bulk_count}, max_buffer_bytesize = #{@max_buffer_bytesize}" }
      handle_kafka_server_exception(e)
      raise
    end

    def abort_transaction
      Rails.logger.error('KafkaJava::Producer.abort_transaction') { "There is no pending_transaction" } if @pending_transaction.nil?
      Rails.logger.debug('KafkaJava::Producer.abort_transaction') { "Aborting transaction" }
      @kafka_producer&.abortTransaction
    rescue Exception => e
      Rails.logger.error('KafkaJava::Producer.abort_transaction') { "#{e.class} #{e.message} during abort of transaction" }
      raise
    ensure
      @pending_transaction = nil                                                # Mark transaction as inactive by setting to nil
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
    def produce(message:, table:, key: nil, headers: {})
      topic = table.topic_to_use
      record = key.nil? ?
                 org.apache.kafka.clients.producer.ProducerRecord.new(topic, message) :
                 org.apache.kafka.clients.producer.ProducerRecord.new(topic, key, message)
      headers.each do | hkey, hvalue|
        record.headers.add(org.apache.kafka.common.header.internals.RecordHeader.new(hkey.to_s, java.lang.String.new(hvalue.to_s).getBytes))
      end

      @kafka_producer.send(record)                                              # Send message to Kafka

      @topic_infos[topic] = { max_produced_message_size: message.bytesize } if !@topic_infos.has_key?(topic) || message.bytesize > @topic_infos[topic][:max_produced_message_size]
    rescue Exception => e
      Rails.logger.error('KafkaJava::Producer.produce') { "#{e.class} #{e.message} max_buffer_size = #{max_message_bulk_count}, max_buffer_bytesize = #{@max_buffer_bytesize}" }
      handle_kafka_server_exception(e)
      handle_kafka_buffer_overflow(e, message, topic, table) if e.class == Kafka::BufferOverflow
      # TODO: find corresponding Java exception for Kafka::BufferOverflow
      raise
    end

    # send a batch of messages cumulated by produce() to Kafka
    # This method is not needed for KafkaJava, but is required for KafkaRuby
    # @return [void]
    def deliver_messages
    end

    # Cancel previous producer and recreate again

    def reset_kafka_producer
      shutdown                                                                  # free kafka connections of current producer if != nil
      create_kafka_producer                                                     # get fresh producer
    end

    def shutdown
      Rails.logger.info('KafkaJava::Producer.shutdown') { "Shutdown the Kafka producer" }
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

    # Handle exceptions at message production. Can be raised by producer.send and producer.commit_transaction
    # Reraise of exception should be done by caller
    # @param exception [Exception] Exception raised by producer
    # @param caller [String] Name of the calling method
    def handle_kafka_server_exception(exception)
      fix_message_size_too_large if exception.class == Java::OrgApacheKafkaCommonErrors::RecordTooLargeException

      if exception.class == Kafka::ConcurrentTransactionError
        raise KafkaBase::ConcurrentTransactionError.new(exception.message)              # Use generic error class to avoid dependency on Ruby-Kafka gem
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
    props.put('bootstrap.servers',  MovexCdc::Application.config.kafka_seed_broker)  # Kafka bootstrap server as default if not overwritten by file_props

    # Content of property file should overrule the default properties from environment or run_config
    file_props = read_java_properties
    security_protocol = define_security_protocol(file_props)
    props.put('security.protocol', security_protocol) # Ensure that security.protocol is set even if not in file

    case security_protocol
    when nil then
      raise "Missing value for KAFKA_SECURITY_PROTOCOL. Please set this environment variable or define it in the properties file."
    when 'PLAINTEXT' then

    when 'SASL_PLAINTEXT' then
      props.put("sasl.mechanism", "PLAIN") unless file_props[:'sasl.mechanism']
      props.put("sasl.jaas.config", "org.apache.kafka.common.security.plain.PlainLoginModule required username='#{MovexCdc::Application.config.kafka_sasl_plain_username}' password='#{MovexCdc::Application.config.kafka_sasl_plain_password.gsub(/'/, '\\\\\0')}';") unless file_props[:'sasl.jaas.config']
    when 'SASL_SSL' then
      props.put("sasl.mechanism", "PLAIN") unless file_props[:'sasl.mechanism']
      props.put("sasl.jaas.config", "org.apache.kafka.common.security.plain.PlainLoginModule required username='#{MovexCdc::Application.config.kafka_sasl_plain_username}' password='#{MovexCdc::Application.config.kafka_sasl_plain_password.gsub(/'/, '\\\\\0')}';") unless file_props[:'sasl.jaas.config']
      set_ssl_encryption_properties(props, file_props)
    when 'SSL' then
      set_ssl_encryption_properties(props, file_props)
      set_ssl_authentication_properties(props, file_props)
    else
      raise "Unsupported value '#{security_protocol}' for KAFKA_SECURITY_PROTOCOL."
    end

    # Content of property file should overrule the default properties from environment or run_config
    file_props.each do |key, value|# use the whole content of file for connect properties or empty hash if file not specified
      props.put(key, value)
    end
    Rails.logger.debug('KafkaJava.connect_properties') { "properties = #{props}" }
    props
  end

  # Define the final security protocol to use for Kafka connection
  # @param file_props [Hash] Properties read from the properties file
  # @return [String] security protocol to use for Kafka connection
  def define_security_protocol(file_props)
    file_props[:'security.protocol'] || MovexCdc::Application.config.kafka_security_protocol || 'PLAINTEXT'
  end

  # Validate the connection properties at startup to raise the exception before worker threads are started
  # @raise [Exception] if connection properties are invalid
  def validate_connect_properties
    required_properties = {
      'PLAINTEXT'       => ['bootstrap.servers'],
      'SASL_PLAINTEXT'  => ['bootstrap.servers', 'sasl.jaas.config'],
      'SASL_SSL'        => ['bootstrap.servers', 'sasl.jaas.config', 'ssl.key.password'],
      'SSL'             => ['bootstrap.servers', 'ssl.key.password']
    }

    notneeded_properties = {
      'PLAINTEXT'       => ['sasl.jaas.config', 'ssl.truststore.certificates', 'ssl_truststore_location', 'ssl_truststore_password', 'ssl_keystore_location', 'ssl_keystore_password', 'ssl_key_password', 'ssl.keystore.type', 'ssl_client_cert', 'ssl_client_cert_chain', 'ssl_client_cert_key'],
      'SASL_PLAINTEXT'  => ['ssl.truststore.certificates', 'ssl_truststore_location', 'ssl_truststore_password', 'ssl_keystore_location', 'ssl_keystore_password', 'ssl_key_password', 'ssl.keystore.type', 'ssl_client_cert', 'ssl_client_cert_chain', 'ssl_client_cert_key'],
      'SASL_SSL'        => ['ssl_keystore_location', 'ssl_keystore_password', 'ssl_key_password', 'ssl.keystore.type', 'ssl_client_cert', 'ssl_client_cert_chain', 'ssl_client_cert_key'],
      'SSL'             => ['sasl.jaas.config']
    }

    properties = read_java_properties                                           # read the properties from the config file if defined
    security_protocol = define_security_protocol(properties)
    raise "Unsupported value '#{security_protocol}' for KAFKA_SECURITY_PROTOCOL." unless ['PLAINTEXT', 'SASL_PLAINTEXT', 'SASL_SSL', 'SSL'].include?(security_protocol)

    # @type [Proc] Check a particular property for validity
    # @param rails_config_name [Symbol] Name of the property in MovexCdc::Application.config
    # @param file_property_name [Symbol] Name of the property in the Kafka property file
    validate_connect_property = proc do |rails_config_name, file_property_name|
      # Ensure only one source defines the property
      if MovexCdc::Application.config.send(rails_config_name) && properties[file_property_name]
        raise "Conflicting settings for #{rails_config_name} (#{MovexCdc::Application.config.send(rails_config_name)}) and '#{file_property_name}' in KAFKA_PROPERTIES_FILE (#{properties[file_property_name]}). Property should be defined at one location only."
      end
      # Check not needed
      if (MovexCdc::Application.config.send(rails_config_name) || properties[file_property_name]) && notneeded_properties[security_protocol].include?(file_property_name.to_s)
        msg = if MovexCdc::Application.config.send(rails_config_name)
          "Unnecessary configuration value for #{rails_config_name.upcase} if security protocol = #{security_protocol}. Please remove this configuration attribute."
        else
          "Unnecessary configuration value for '#{file_property_name}' in KAFKA_PROPERTIES_FILE if security protocol = #{security_protocol}. Please remove this configuration attribute."
        end
        puts msg
        Rails.logger.warn msg
      end

      # Check required
      if MovexCdc::Application.config.send(rails_config_name).nil? && properties[file_property_name].nil?  && required_properties[security_protocol].include?(file_property_name.to_s)
        msg = "Missing required configuration value for #{rails_config_name.upcase} or '#{file_property_name}' in KAFKA_PROPERTIES_FILE if security protocol = #{security_protocol}."
        puts msg
        Rails.logger.warn msg
      end

    end

    validate_connect_property.call(:kafka_security_protocol,    :'security.protocol')
    validate_connect_property.call(:kafka_seed_broker,          :'bootstrap.servers')
    validate_connect_property.call(:kafka_sasl_plain_username,  :'sasl.jaas.config') # Username as part of jaas.config
    validate_connect_property.call(:kafka_sasl_plain_password,  :'sasl.jaas.config') # Password as part of jaas.config
    validate_connect_property.call(:kafka_ssl_truststore_type,  :'ssl.truststore.type') # Default value is JKS

    # Check for SSL encryption properties
    if ['SASL_SSL', 'SSL'].include?(security_protocol)
      if MovexCdc::Application.config.kafka_ssl_truststore_type == 'PEM' || properties[:'ssl.truststore.type'] == 'PEM'
        required_properties[security_protocol] << 'ssl.truststore.certificates' unless MovexCdc::Application.config.kafka_ssl_ca_certs_from_system
        notneeded_properties[security_protocol] << 'ssl_truststore_location'
        notneeded_properties[security_protocol] << 'ssl_truststore_password'
      else # default JKS
        required_properties[security_protocol] << 'ssl_truststore_location'
        required_properties[security_protocol] << 'ssl_truststore_password'
        notneeded_properties[security_protocol] << 'ssl.truststore.certificates'
      end
    end
    validate_connect_property.call(:kafka_ssl_ca_cert,              :'ssl.truststore.certificates')
    validate_connect_property.call(:kafka_ssl_truststore_location,  :'ssl.truststore.location')
    validate_connect_property.call(:kafka_ssl_truststore_password,  :'ssl.truststore.password')

    # Check for SSL authentication properties
    if security_protocol == 'SSL'
      if MovexCdc::Application.config.kafka_ssl_keystore_type == 'PEM' || properties[:'ssl.keystore.type'] == 'PEM'
        required_properties[security_protocol] << 'ssl.keystore.certificate.chain'
        required_properties[security_protocol] << 'ssl.keystore.key'
        notneeded_properties[security_protocol] << 'ssl_keystore_location'
        notneeded_properties[security_protocol] << 'ssl_keystore_password'
        raise "Only one of KAFKA_SSL_CA_CERT or KAFKA_SSL_CA_CERT_CHAIN should be defined." if MovexCdc::Application.config.kafka_ssl_ca_cert && MovexCdc::Application.config.kafka_ssl_ca_cert_chain
      else # default JKS
        required_properties[security_protocol] << 'ssl_keystore_location'
        required_properties[security_protocol] << 'ssl_keystore_password'
        notneeded_properties[security_protocol] << 'ssl.keystore.certificate.chain'
        notneeded_properties[security_protocol] << 'ssl.keystore.key'
      end
    end
    validate_connect_property.call(:kafka_ssl_client_cert_chain, :'ssl.keystore.certificate.chain') unless MovexCdc::Application.config.kafka_ssl_client_cert
    validate_connect_property.call(:kafka_ssl_client_cert      , :'ssl.keystore.certificate.chain') unless MovexCdc::Application.config.kafka_ssl_client_cert_chain
    validate_connect_property.call(:kafka_ssl_client_cert_key  , :'ssl.keystore.key')
    validate_connect_property.call(:kafka_ssl_key_password     , :'ssl.key.password')
    validate_connect_property.call(:kafka_ssl_keystore_location, :'ssl.keystore.location')
    validate_connect_property.call(:kafka_ssl_keystore_password, :'ssl.keystore.password')

    # Check existence of files
    if MovexCdc::Application.config.kafka_ssl_ca_cert
      MovexCdc::Application.config.kafka_ssl_ca_cert.split(',').map{|s| s.strip}.each do |file|
        check_file_existence(file, 'Certificate file', 'defined by KAFKA_SSL_CA_CERT')
      end
    end
    check_file_existence(MovexCdc::Application.config.kafka_ssl_client_cert_chain, 'Certificate file', 'defined by KAFKA_CLIENT_CERT_CHAIN') if MovexCdc::Application.config.kafka_ssl_client_cert_chain
    check_file_existence(MovexCdc::Application.config.kafka_ssl_client_cert,       'Certificate file', 'defined by KAFKA_CLIENT_CERT')       if MovexCdc::Application.config.kafka_ssl_client_cert
    check_file_existence(MovexCdc::Application.config.kafka_ssl_client_cert_key,   'Certificate file', 'defined by KAFKA_CLIENT_CERT_KEY') if MovexCdc::Application.config.kafka_ssl_client_cert_key
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

  # Set SSL encryption properties for Kafka
  # @param [java.util.Properties] properties object to be enriched
  # @param [JavaProperties] file_props properties read from properties file
  # @return [void]
  def set_ssl_encryption_properties(properties, file_props)
    if MovexCdc::Application.config.kafka_ssl_truststore_type == 'PEM' || properties[:'ssl.truststore.type'] == 'PEM'
      properties.put('ssl.truststore.type',         MovexCdc::Application.config.kafka_ssl_truststore_type) unless file_props[:'ssl.truststore.type']

      if MovexCdc::Application.config.kafka_ssl_ca_cert
        certs = ''
        MovexCdc::Application.config.kafka_ssl_ca_cert.split(',').map{|s| s.strip}.each do |cert|
          certs << File.read(cert)
          certs << "\n"
        end
        properties.put('ssl.truststore.certificates', certs);
      end
    else # JKS
      properties.put('ssl.truststore.location', MovexCdc::Application.config.kafka_ssl_truststore_location) unless file_props[:'ssl.truststore.location']
      properties.put('ssl.truststore.password', MovexCdc::Application.config.kafka_ssl_truststore_password) unless file_props[:'ssl.truststore.password']
    end
  end

  # Set SSL authentication properties for Kafka
  # @param [java.util.Properties] properties object to be enriched
  # @param [JavaProperties] file_props properties read from properties file
  # @return [void]
  def set_ssl_authentication_properties(properties, file_props)
    if MovexCdc::Application.config.kafka_ssl_keystore_type == 'PEM' || properties[:'ssl.keystore.type'] == 'PEM'
      properties.put('ssl.keystore.type',               MovexCdc::Application.config.kafka_ssl_keystore_type) unless file_props[:'ssl.keystore.type']
      properties.put('ssl.keystore.certificate.chain',  File.read(MovexCdc::Application.config.kafka_ssl_client_cert_chain))  if MovexCdc::Application.config.kafka_ssl_client_cert_chain
      properties.put('ssl.keystore.key',                File.read(MovexCdc::Application.config.kafka_ssl_client_cert_key))    if MovexCdc::Application.config.kafka_ssl_client_cert_key
      properties.put(ssl.key.password,                  MovexCdc::Application.config.kafka_ssl_key_password)                  if MovexCdc::Application.config.kafka_ssl_key_password
    else # JKS
      properties.put('ssl.keystore.location', MovexCdc::Application.config.kafka_ssl_keystore_location) unless file_props[:'ssl.keystore.location']
      properties.put('ssl.keystore.password', MovexCdc::Application.config.kafka_ssl_keystore_password) unless file_props[:'ssl.keystore.password']
      properties.put('ssl.key.password',      MovexCdc::Application.config.kafka_ssl_key_password)      unless file_props[:'ssl.key.password'] # The password of the private key in the key store file. This is optional for client.
    end
  end

  # Get properties from a property file
  # @return [JavaProperties|Hash] properties from property file or empty Hash if no property file is defined
  def read_java_properties
    file_path = MovexCdc::Application.config.kafka_properties_file
    if file_path.nil?
      {}
    else
      # Check if file exists
      check_file_existence(file_path, 'Property file', 'defined by KAFKA_PROPERTIES_FILE')
      # Read the property file
      properties = JavaProperties.load(file_path)
      properties
    end
  end


  def check_file_existence(filepath, description_prefix, description_suffix=nil)
    raise "#{description_prefix} '#{filepath}' #{description_suffix}#{' ' if description_suffix}does not exist."   unless File.exist?(filepath)
    raise "#{description_prefix} '#{filepath}' #{description_suffix}#{' ' if description_suffix}is not a file."    unless File.file?(filepath)
    raise "#{description_prefix} '#{filepath}' #{description_suffix}#{' ' if description_suffix}is not readable."  unless File.readable?(filepath)
  end
end