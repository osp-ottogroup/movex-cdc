class KafkaMock
  class Producer
    def intialize(options)

    end

    def produce(message, options)

    end

    def deliver_messages

    end

    def clear_buffer

    end

    def shutdown

    end

    def transaction(&block)
      block.call
    end
  end


  def initialize(seed_broker, options)

  end

  def producer
    Producer.new
  end

end