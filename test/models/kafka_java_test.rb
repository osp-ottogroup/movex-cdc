require 'test_helper'

class KafkaJavaTest < ActiveSupport::TestCase
  test "validate_connect_properties" do
    org_kafka_security_protocol   = MovexCdc::Application.config.kafka_security_protocol
    org_kafka_properties_file     = MovexCdc::Application.config.kafka_properties_file
    org_kafka_sasl_plain_username = MovexCdc::Application.config.kafka_sasl_plain_username

    MovexCdc::Application.config.kafka_security_protocol = 'PLAINTEXT'
    MovexCdc::Application.config.kafka_properties_file = nil
    KafkaJava.new.validate_connect_properties # Should not raise beacuse only one value is set for security.protocol

    MovexCdc::Application.config.kafka_security_protocol = nil
    MovexCdc::Application.config.kafka_properties_file = 'kafka.properties'
    File.write('kafka.properties', 'security.protocol=PLAINTEXT')
    KafkaJava.new.validate_connect_properties # Should not raise beacuse only one value is set for security.protocol

    assert_raises(Exception) do
      MovexCdc::Application.config.kafka_security_protocol = 'PLAINTEXT'
      File.write('kafka.properties', 'security.protocol=PLAINTEXT')
      KafkaJava.new.validate_connect_properties # Should not raise exception because values are identical
      assert false, 'Should not get here because definition from two sources should raise exception'
    end

    assert_raises(Exception) do
      MovexCdc::Application.config.kafka_security_protocol = nil
      MovexCdc::Application.config.kafka_properties_file = nil
      KafkaJava.new.validate_connect_properties
      assert false, 'Should not get here because security_protocol required'
    end

    assert_raises(Exception) do
      MovexCdc::Application.config.kafka_security_protocol = 'SASL_PLAINTEXT'
      MovexCdc::Application.config.kafka_properties_file = 'kafka.properties'
      File.write('kafka.properties', 'security.protocol=SSL')
      KafkaJava.new.validate_connect_properties
      assert false, 'Should not get here because SASL_PLAINTEXT is conflicting with SSL and defined at two places'
    end
    MovexCdc::Application.config.kafka_properties_file = nil                    # Restore previous value

    assert_log_written('WARN -- : Unnecessary configuration value for KAFKA_SASL_PLAIN_USERNAME if security protocol = PLAINTEXT') do
      MovexCdc::Application.config.kafka_security_protocol = 'PLAINTEXT'
      MovexCdc::Application.config.kafka_sasl_plain_username = 'hugo'
      KafkaJava.new.validate_connect_properties
    end

    # Check SSL combinations
    assert_log_written("Possibly missing required configuration value for KAFKA_SSL_CLIENT_CERT_CHAIN or 'ssl.keystore.certificate.chain' in KAFKA_PROPERTIES_FILE if security protocol = SSL") do
      MovexCdc::Application.config.kafka_security_protocol = 'SSL'
      MovexCdc::Application.config.kafka_ssl_keystore_type = 'PEM'
      KafkaJava.new.validate_connect_properties
    end

    # Restore original values
    MovexCdc::Application.config.kafka_security_protocol    = org_kafka_security_protocol
    MovexCdc::Application.config.kafka_properties_file      = org_kafka_properties_file
    MovexCdc::Application.config.kafka_sasl_plain_username  = org_kafka_sasl_plain_username
  end
end
