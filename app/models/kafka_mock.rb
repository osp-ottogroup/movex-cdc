require 'json'

EXISTING_TOPICS = ['Topic1', 'Topic2']

class KafkaMock < KafkaBase
  class Producer < KafkaBase::Producer
    # Create producer instance
    # @param [KafkaMock] kafka Instance of KafkaMock
    # @param [String] transactional_id Transactional id for the producer
    # @return [void]
    def initialize(kafka, transactional_id:)
      @last_produced_id = 0                                                     # Check messages with key for proper ascending order
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
      msg_hash = JSON.parse message                                             # ensure correct JSON notation
      # Rails.logger.debug('KafkaMock.produce'){msg_hash}                       # only for special tests, may be commented out
      if key                                                                    # for keyed messages ID should be ascending
        # suspended until decision about fixing JSON error in PK keys
        JSON.parse key if key[0] == '{'                     # key should contain valid JSON if Key contains JSON (e.g. for primary key)
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
    rescue JSON::ParserError => e
      msg = "#{e.class} #{e.message} while parsing #{message}"
      Rails.logger.error('KafkaMock.produce'){ msg }
      raise msg
    end

    def deliver_messages
      @events.each do |event|
        raise "KafkaMock::Producer.deliver_messages: No topic for event #{event}" unless @kafka.has_topic?(event[:topic])
      end
      @events = []
    end

    def reset_kafka_producer
    end

    def shutdown;
    end

  end # class Producer


  private
  def initialize
    super()
    @producer = nil                                                             # KafkaMock::Producer is not initialized until needed
  end

  public

  # @return [Array] List of Kafka topic names
  def topics
    EXISTING_TOPICS.sort
  end

  # @param topic [String] Kafka topic name to check for existence
  # @return [Boolean] True if the topic exists
  def has_topic?(topic)
    topics.include?(topic)
  end

  # @param topic [String] Kafka topic name to describe
  # @param configs [Array] List of Kafka topic attributes to describe
  # @return [Hash] Description of the Kafka topic
  def describe_topic(topic, configs = [])
    if EXISTING_TOPICS.include? topic
      {"max.message.bytes"=>"100000", "retention.ms"=>"604800000"}
    else
      raise "Not existing topic '#{topic}'"
    end
  end

  # Describe a single Kafka topic attribute
  # @param topic [String] Kafka topic name to describe
  # @param attribute [String] Kafka topic attribute to describe
  # @return [String] Value of the Kafka topic attribute
  def describe_topic_attr(topic, attribute)
    describe_topic(topic, [attribute])[attribute]
  end

  # @param topic [String] Kafka topic name to describe with all attributes
  # @return [Hash] Description of the Kafka topic
  def describe_topic_complete(topic)
    if EXISTING_TOPICS.include? topic
      {
        partitions: 2,
        replicas: 2,
        last_offsets: { topic => { '0': 5, '1': 8 }},
        leaders: { '0': '1', '1': '1' },
        config: { 'max.message.bytes': { value: 100000, info: 'Hugo'}, 'retention.ms': { value: "604800000", info: 'Hugo' }}
      }
    else
      raise "Not existing topic '#{topic}'"
    end
  end

  # Change topic settings
  # @param topic [String] Kafka topic name to change
  # @param settings [Hash] Settings to change
  def  alter_topic(topic, settings)
    @kafka.alter_topic(topic, settings)
  end

  # @return [Array] List of Kafka group names
  def groups
    @kafka.groups
  end

  # Get the description of a Kafka group (consumer group)
  # @param group_id [Integer] Kafka group id
  # @return [Hash] Description of the Kafka group
  def describe_group(group_id)
    @kafka.describe_group(group_id)
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

  def partitions_for(topic)
    if EXISTING_TOPICS.include? topic
      2
    else
      raise "Not existing topic '#{topic}'"
    end
  end

  def replica_count_for(topic)
    if EXISTING_TOPICS.include? topic
      1
    else
      raise "Not existing topic '#{topic}'"
    end
  end

  def last_offsets_for(topic)
    if EXISTING_TOPICS.include? topic
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
end