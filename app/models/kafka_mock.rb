class KafkaMock
  class Producer
    def intialize(options)
    end

    def produce(message, options)
#      Rails.logger.debug "KafkaMock.produce: options = #{options}, message=\n#{message}"
    end

    def deliver_messages
    end

    def clear_buffer
    end

    def shutdown
    end

    def init_transactions
    end

    def transaction(&block)
      block.call
    end
  end


  def initialize(seed_broker, options)
  end

  def producer(options = {})
    Producer.new
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