module KafkaHelper

  # create connection to Kafka and return instance of class Kafka
  def self.connect_kafka
    kafka_class = MovexCdc::Application.config.kafka_seed_broker == '/dev/null' ? KafkaMock : Kafka
    seed_brokers = MovexCdc::Application.config.kafka_seed_broker.split(',').map{|b| b.strip}

    kafka_options = {
        client_id: "MOVEX-CDC-#{Socket.gethostname}",
        logger: Rails.logger
    }
    kafka_options[:ssl_ca_certs_from_system]      = true if MovexCdc::Application.config.kafka_ssl_ca_certs_from_system.is_a? (TrueClass) || MovexCdc::Application.config.kafka_ssl_ca_certs_from_system == 'TRUE'
    # kafka_options[:ssl_ca_cert]                   = File.read(MovexCdc::Application.config.kafka_ssl_ca_cert)           if MovexCdc::Application.config.kafka_ssl_ca_cert
    # config.kafka_ssl_ca_cert may be a single file path or a comma-separated list of file paths
    kafka_options[:ssl_ca_cert_file_path]         = MovexCdc::Application.config.kafka_ssl_ca_cert.split(',').map{|s| s.strip}  if MovexCdc::Application.config.kafka_ssl_ca_cert
    kafka_options[:ssl_client_cert_chain]         = File.read(MovexCdc::Application.config.kafka_ssl_client_cert_chain) if MovexCdc::Application.config.kafka_ssl_client_cert_chain
    kafka_options[:ssl_client_cert]               = File.read(MovexCdc::Application.config.kafka_ssl_client_cert)       if MovexCdc::Application.config.kafka_ssl_client_cert
    kafka_options[:ssl_client_cert_key]           = File.read(MovexCdc::Application.config.kafka_ssl_client_cert_key)   if MovexCdc::Application.config.kafka_ssl_client_cert_key
    kafka_options[:ssl_client_cert_key_password]  = MovexCdc::Application.config.kafka_ssl_client_cert_key_password     if MovexCdc::Application.config.kafka_ssl_client_cert_key_password
    # kafka_options[:ssl_verify_hostname]           = false
    kafka_options[:sasl_plain_username]  = MovexCdc::Application.config.kafka_sasl_plain_username if MovexCdc::Application.config.kafka_sasl_plain_username
    kafka_options[:sasl_plain_password]  = MovexCdc::Application.config.kafka_sasl_plain_password if MovexCdc::Application.config.kafka_sasl_plain_password
    kafka_class.new(seed_brokers, kafka_options)                                # return instance of Kafka
  end

  # Check topic for existence at Kafka
  def self.has_topic?(topic)
    kafka = KafkaHelper.connect_kafka                                           # gets instance of class Kafka
    kafka.has_topic?(topic)
  end

  @@existing_topic_for_test = nil
  # get name of existing topic and cache for lifetime
  def self.existing_topic_for_test
    if @@existing_topic_for_test.nil?
      kafka = KafkaHelper.connect_kafka                                         # gets instance of class Kafka
      topics = kafka.topics
      raise "No topic configured yet at Kafka" if topics.length == 0
      test_topics = topics.select {|t| !t['__']}                                # discard all topics with '__' like '__consumer_offsets', '__transaction_state' etc.
      @@existing_topic_for_test = test_topics[0]                                # use first remaining topic as sample
    end
    @@existing_topic_for_test
  end

  @@existing_group_id_for_test = nil
  # get name of existing group and cache for lifetime
  def self.existing_group_id_for_test
    if @@existing_group_id_for_test.nil?
      kafka = KafkaHelper.connect_kafka                                         # gets instance of class Kafka
      groups = kafka.groups
      raise "No consumer group configured yet at Kafka" if groups.length == 0
      @@existing_group_id_for_test = groups[0]                                  # use first existing group as sample
    end
    @@existing_group_id_for_test
  end

end