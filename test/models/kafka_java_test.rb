require 'test_helper'

class KafkaJavaTest < ActiveSupport::TestCase
  test "validate_connect_properties" do
    org_kafka_security_protocol   = MovexCdc::Application.config.kafka_security_protocol
    org_kafka_properties_file     = MovexCdc::Application.config.kafka_properties_file
    org_kafka_sasl_plain_username = MovexCdc::Application.config.kafka_sasl_plain_username

    MovexCdc::Application.config.kafka_security_protocol = 'PLAINTEXT'
    MovexCdc::Application.config.kafka_properties_file = nil
    KafkaJava.new.validate_connect_properties # Should not raise

    MovexCdc::Application.config.kafka_security_protocol = nil
    MovexCdc::Application.config.kafka_properties_file = 'kafka.properties'
    File.write('kafka.properties', 'security.protocol=PLAINTEXT')
    KafkaJava.new.validate_connect_properties # Should not raise beacuse only one value is set for security.protocol

    MovexCdc::Application.config.kafka_security_protocol = 'PLAINTEXT'
    File.write('kafka.properties', 'security.protocol=PLAINTEXT')
    KafkaJava.new.validate_connect_properties # Should not raise exception because values are identical

    assert_raises(Exception) do
      MovexCdc::Application.config.kafka_security_protocol = nil
      MovexCdc::Application.config.kafka_properties_file = nil
      KafkaJava.new.validate_connect_properties
    end

    assert_raises(Exception) do
      MovexCdc::Application.config.kafka_security_protocol = 'SASL_PLAINTEXT'
      MovexCdc::Application.config.kafka_properties_file = 'kafka.properties'
      File.write('kafka.properties', 'security.protocol=SSL')
      KafkaJava.new.validate_connect_properties
      assert false, 'Should not get here because SASL_PLAINTEXT is conflicting with SSL'
    end
    MovexCdc::Application.config.kafka_properties_file = nil                    # Restore previous value

    assert_log_written('WARN -- : Unnecessary configuration value for KAFKA_SASL_PLAIN_USERNAME if security protocol = PLAINTEXT') do
      MovexCdc::Application.config.kafka_security_protocol = 'PLAINTEXT'
      MovexCdc::Application.config.kafka_sasl_plain_username = 'hugo'
      KafkaJava.new.validate_connect_properties
    end

    # Restore original values
    MovexCdc::Application.config.kafka_security_protocol    = org_kafka_security_protocol
    MovexCdc::Application.config.kafka_properties_file      = org_kafka_properties_file
    MovexCdc::Application.config.kafka_sasl_plain_username  = org_kafka_sasl_plain_username
  end
end
