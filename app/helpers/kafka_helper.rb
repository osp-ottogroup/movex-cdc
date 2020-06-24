module KafkaHelper

  # create connection to Kafka and return instance of class Kafka
  def self.connect_kafka
    kafka_class = Trixx::Application.config.trixx_kafka_seed_broker == '/dev/null' ? KafkaMock : Kafka
    seed_brokers = Trixx::Application.config.trixx_kafka_seed_broker.split(',').map{|b| b.strip}

    kafka_options = {
        client_id: "TriXX: TRIXX-#{Socket.gethostname}",
        logger: Rails.logger
    }
    kafka_options[:ssl_ca_cert]                   = File.read(Trixx::Application.config.trixx_kafka_ssl_ca_cert)          if Trixx::Application.config.trixx_kafka_ssl_ca_cert
    kafka_options[:ssl_client_cert]               = File.read(Trixx::Application.config.trixx_kafka_ssl_client_cert)      if Trixx::Application.config.trixx_kafka_ssl_client_cert
    kafka_options[:ssl_client_cert_key]           = File.read(Trixx::Application.config.trixx_kafka_ssl_client_cert_key)  if Trixx::Application.config.trixx_kafka_ssl_client_cert_key
    kafka_options[:ssl_client_cert_key_password]  = Trixx::Application.config.trixx_kafka_ssl_client_cert_key_password    if Trixx::Application.config.trixx_kafka_ssl_client_cert_key_password

    kafka_class.new(seed_brokers, kafka_options)                                # return instance of Kafka
  end

  # Check topic for existence at Kafka
  def self.has_topic?(topic)
    kafka = KafkaHelper.connect_kafka                                           # gets instance of class Kafka
    kafka.has_topic?(topic)
  end

  # get name of existing topic
  def self.existing_topic_for_test
    kafka = KafkaHelper.connect_kafka                                           # gets instance of class Kafka
    topics = kafka.topics
    raise "No topic configured yet at Kafka" if topics.length == 0
    topics.delete '__consumer_offsets'                                          # remove possibly existing default topic
    topics[0]                                                                   # use first remaining topic as sample
  end

  def self.existing_group_id_for_test
    kafka = KafkaHelper.connect_kafka                                           # gets instance of class Kafka
    groups = kafka.groups
    raise "No consumer group configured yet at Kafka" if groups.length == 0
    groups[0]                                                                   # use first existing group as sample
  end

end