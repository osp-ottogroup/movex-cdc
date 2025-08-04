require 'json'

class KafkaMock < KafkaBase
  class Producer < KafkaBase::Producer
    # Create producer instance
    # @param [KafkaMock] kafka Instance of KafkaMock
    # @param [String] transactional_id Transactional id for the producer
    # @return [void]
    def initialize(kafka, transactional_id:)
      @last_produced_id = 0                                                     # Check messages with key for proper ascending order
      @last_successfully_delivered_id = 0
      super(kafka, transactional_id: transactional_id)
      @events = []
    end

    def begin_transaction
    end

    def commit_transaction
    end

    def abort_transaction
    end

    def clear_buffer
    end

    # Create a single Kafka message
    # @param [String] message Message to send
    # @param [Table] table Table object of the message
    # @param [String] key Key of the message
    # @param [Hash] headers Headers of the message
    def produce(message:, table:, key:, headers:)
      raise "KafkaMock::MessageSizeTooLargeException" if message.bytesize > 1024*1024 # identical behavior like Kafka default for message.max.size
      msg_hash = begin
                  JSON.parse message                                            # ensure correct JSON notation
                 rescue JSON::ParserError => e
                   msg = "#{e.class} #{e.message} while parsing message = #{message}"
                   Rails.logger.error('KafkaMock.produce'){ msg }
                   raise msg
                 end
      validate_message_content(msg_hash)

      # Rails.logger.debug('KafkaMock.produce'){msg_hash}                       # only for special tests, may be commented out
      if key                                                                    # for keyed messages ID should be ascending
        # suspended until decision about fixing JSON error in PK keys
        begin
          JSON.parse key if key[0] == '{'                     # key should contain valid JSON if Key contains JSON (e.g. for primary key)
        rescue JSON::ParserError => e
          msg = "#{e.class} #{e.message} while parsing key = #{key}"
          Rails.logger.error('KafkaMock.produce'){ msg }
          raise msg
        end
        next_id = msg_hash['id'].to_i
        if next_id <= @last_produced_id
          raise "KafkaMock::Producer.produce: Ascending order of IDs violated for messages with key! Current ID = #{next_id}, Last used ID = #{@last_produced_id}"
        end
        @last_produced_id = next_id
      end

      case msg_hash['tablename']
      when 'VICTIM1' then
        raise 'Events for table VICTIM1 should have event headers! Missing header ce_id' if !headers.has_key?(:ce_id)
      when 'VICTIM2' then
        raise 'Events for table VICTIM2 should not have event headers' if headers.count > 0
      end
      @events << { message: message, topic: table.topic_to_use, key: key, headers: headers}
    end

    def deliver_messages
      @events.each do |event|
        unless @kafka.has_topic?(event[:topic])
          @last_produced_id = @last_successfully_delivered_id                   # reset last produced ID because events will occur again
          raise "KafkaMock::Producer.deliver_messages: No topic for event #{event}"
        end
      end
      @last_successfully_delivered_id = @last_produced_id                       # remember last successfully delivered ID
    ensure
      @events = []                                                              # ensure to start with empty event list even after repeated errors
    end

    def reset_kafka_producer
    end

    def shutdown;
    end

    private
    # Check if the message content is valid
    # @param msg_hash [Hash] Parsed message content to validate
    # @raise [Exception] if the message content is invalid
    # @return [void]
    def validate_message_content(msg_hash)
      raise "Message content is not a Hash!" if !msg_hash.is_a?(Hash)

      raise "ID is not numeric" unless msg_hash['id'].to_i.is_a? Integer

      raise "schema is not a String" unless msg_hash['schema'].is_a? String
      raise "schema is empty" if msg_hash['schema'].empty?

      raise "tablename is not a String" unless msg_hash['tablename'].is_a? String
      raise "tablename is empty" if msg_hash['tablename'].empty?

      raise "operation is not a String" unless msg_hash['operation'].is_a? String
      raise "operation is empty" if msg_hash['operation'].empty?
      raise "operation is not valid" unless ['INIT', 'INSERT', 'UPDATE', 'DELETE'].include? msg_hash['operation']

      raise "timestamp is not a String" unless msg_hash['timestamp'].is_a? String
      raise "timestamp is empty" if msg_hash['timestamp'].empty?
      DateTime.parse(msg_hash['timestamp'])                                     # All types of LEGACY_TS_FORMAT should be valid for DateTime.parse
      case MovexCdc::Application.config.legacy_ts_format
      when nil, '' then
        raise "timestamp should contain colon" unless msg_hash['timestamp'].include?(':')
        raise "timestamp should contain not comma as fraction delimiter" if msg_hash['timestamp'].include?(',')
        raise "timestamp should contain dot as fraction delimiter" unless msg_hash['timestamp'].include?('.')
      when 'TYPE_1' then
        raise "timestamp should not contain colon" if msg_hash['timestamp'].include?(':')
        raise "timestamp should not have a timezone other than +0000" if !msg_hash['timestamp'].include?('+0000')
        raise "timestamp should contain comma as fraction delimiter" if !msg_hash['timestamp'].include?(',')
      when 'TYPE_2' then
        raise "timestamp should contain colon" unless msg_hash['timestamp'].include?(':')
        raise "timestamp should contain comma as fraction delimiter" if !msg_hash['timestamp'].include?(',')
      else
        raise "Unknown legacy timestamp format '#{MovexCdc::Application.config.legacy_ts_format}'"
      end

      raise "transaction_id is not a String" if !msg_hash['transaction_id'].nil? && !msg_hash['transaction_id'].is_a?(String)

      raise "new is not a Hash" if !msg_hash['new'].nil? && !msg_hash['new'].is_a?(Hash)

      raise "old is not a Hash" if !msg_hash['new'].nil? && !msg_hash['new'].is_a?(Hash)
    rescue Exception => e
      raise "KafkaMock::Producer.validate_message_content: #{e.message}"
    end
  end # class Producer


  private
  def initialize
    super()
    @producer = nil                                                             # KafkaMock::Producer is not initialized until needed
    @topic_attrs = {"max.message.bytes"=>"100000", "retention.ms"=>"604800000"}
    @groups = [
      { group_id: 'group1', state: 'Stable', protocol_type: 'consumer', protocol: 'roundrobin', members: [{ member_id: 'member1', client_id: 'client1', client_host: 'host1', metadata: 'metadata1', assignment: 'assignment1' }]},
      { group_id: 'group2', state: 'Stable', protocol_type: 'consumer', protocol: 'roundrobin', members: [{ member_id: 'member1', client_id: 'client1', client_host: 'host1', metadata: 'metadata1', assignment: 'assignment1' }]},
    ]
  end

  public

  # @return [Array] List of Kafka topic names
  def topics
    if !defined?(@topics) || @topics.nil?
      # Two default topics for testing
      topics = ['Topic1', 'Topic2']
      Schema.all.each do |schema|
        topics << schema.topic unless schema.topic.nil?
      end
      Table.all.each do |table|
        topics << table.topic unless table.topic.nil?
      end

      topics.delete('Non-existing topic')                                       # Should raise error in test if used

      @topics = topics.uniq.sort
    end
    @topics
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
    @topic_attrs[attribute].to_s
  end

  # @param topic [String] Kafka topic name to describe with all attributes
  # @return [Hash] Description of the Kafka topic
  def describe_topic_complete(topic)
    if topics.include? topic
      {
        partitions: 2,
        replicas: 2,
        last_offsets: { topic => { '0': 5, '1': 8 }},
        leaders: { '0': '1', '1': '1' },
        config: { 'max.message.bytes': { value: @topic_attrs['max.message.bytes'], info: 'Hugo'}, 'retention.ms': { value: @topic_attrs['retention.ms'], info: 'Hugo' }}
      }
    else
      raise "Not existing topic '#{topic}'"
    end
  end

  # Change topic settings
  # @param topic [String] Kafka topic name to change
  # @param settings [Hash] Settings to change
  def  alter_topic(topic, settings)
    @topic_attrs.merge!(settings)
  end

  # @return [Array] List of Kafka group names
  def groups
    @groups.map{|g| g[:group_id]}
  end

  # Get the description of a Kafka group (consumer group)
  # @param group_id [Integer] Kafka group id
  # @return [Hash] Description of the Kafka group
  def describe_group(group_id)
    @groups.find{|g| g[:group_id] == group_id}
  end


  # Create instance of KafkaMock::Producer
  # @param transactional_id [String] Transactional id for the producer
  # @return [KafkaMock::Producer] Instance of KafkaMock::Producer
  def create_producer(transactional_id:)
    if @producer.nil?
      @producer = Producer.new(self, transactional_id: transactional_id)
    else
      raise "KafkaMock::create_producer: producer already initialized! Only one producer per instance allowed."
    end
    @producer
  end

  # @return [KafkaMock::Producer] Instance of KafkaMock::Producer if exists
  def producer
    if @producer.nil?
      raise "KafkaMock::producer: producer not yet created! Call KafkaMock::create_producer(options) first."
    else
      @producer
    end
  end

  def partitions_for(topic)
    if topics.include? topic
      2
    else
      raise "Not existing topic '#{topic}'"
    end
  end

  def replica_count_for(topic)
    if topics.include? topic
      1
    else
      raise "Not existing topic '#{topic}'"
    end
  end

  def last_offsets_for(topic)
    if topics.include? topic
      { topic => {'0': 5, '1': 8} }
    else
      raise "Not existing topic '#{topic}'"
    end
  end

  EXISTING_GROUPS = ['Group1', 'Group2']
  def groups
    EXISTING_GROUPS
  end

  def describe_group(group_id)
    if EXISTING_GROUPS.include? group_id
      {"max.message.bytes"=>"100000", "retention.ms"=>"604800000"}
    else
      raise "Not existing group '#{group_id}'"
    end
  end

  # Validate the connection properties at startup
  # @raise [Exception] if connection properties are invalid
  def validate_connect_properties

  end
end