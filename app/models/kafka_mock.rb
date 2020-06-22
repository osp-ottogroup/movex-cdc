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

  def topics
    ['Topic1', 'Topic2']
  end

  def describe_topic(topic)
    if ['Topic1', 'Topic2'].include? topic
      {"max.message.bytes"=>"100000", "retention.ms"=>"604800000"}
    else
      raise "Not existing topic '#{topic}'"
    end
  end
end