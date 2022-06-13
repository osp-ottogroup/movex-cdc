require 'json'

class KafkaMock
  class Producer
    def initialize(options)
      @last_produced_id = 0                                                     # Check messages with key for proper ascending order
    end

    def produce(message, options)
      raise "KafkaMock::MessageSizeTooLargeException" if message.bytesize > 1024*1024 # identical behavior like Kafka default for message.max.size
      msg_hash = JSON.parse message                                             # ensure correct JSON notation
      # Rails.logger.debug('KafkaMock.produce'){msg_hash}                         # only for special tests, may be commented out
      if options[:key]                                                          # for keyed messages ID should be ascending
        # suspended until decision about fixing JSON error in PK keys
        JSON.parse options[:key] if options[:key][0] == '{'                     # key should contain valid JSON if Key contains JSON (e.g. for primary key)
        next_id = msg_hash['id'].to_i
        if next_id <= @last_produced_id
          raise "KafkaMock::Producer.produce: Ascending order of IDs violated for messages with key! Current ID = #{next_id}, Last used ID = #{@last_produced_id}"
        end
        @last_produced_id = next_id
      end
    rescue JSON::ParserError => e
      msg = "#{e.class} #{e.message} while parsing #{message}"
      Rails.logger.error('KafkaMock.produce'){ msg }
      raise msg
#      Rails.logger.debug('KafkaMock.produce'){ "options = #{options}, message=\n#{message}" }
    end

    def deliver_messages
    end

    def clear_buffer
    end

    def shutdown;             end
    def init_transactions;    end
    def begin_transaction;    end
    def commit_transaction;   end
    def abort_transaction;    end

    def transaction(&block)
      block.call
    end
  end


  def initialize(seed_broker, options)
  end

  def producer(options = {})
    Producer.new(options)
  end

  EXISTING_TOPICS = ['Topic1', 'Topic2']
  def topics
    EXISTING_TOPICS
  end

  def describe_topic(topic, configs = [])
    if EXISTING_TOPICS.include? topic
      {"max.message.bytes"=>"100000", "retention.ms"=>"604800000"}
    else
      raise "Not existing topic '#{topic}'"
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

  def has_topic?(topic)
    EXISTING_TOPICS.include? topic
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