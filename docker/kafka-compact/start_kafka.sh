# Start the Kafka service inside the docker container
# Evaluate the SECURITY_PROTOCOL environment variable
# Store SSL config in /tmp/kafka_ssl to mount it into the container

export SERVER_PROPERTIES=$KAFKA_HOME/config/server.properties

export KAFKA_HOST=$HOSTNAME
echo "KAFKA host to use in SSL config, Kafka config and Kafka clients = $KAFKA_HOST"

echo "KAFKA_VERSION = $KAFKA_VERSION"
echo "SCALA_VERSION = $SCALA_VERSION"
sed -i "s|^broker.id=.*$|broker.id=$BROKER_ID|" $SERVER_PROPERTIES
echo "########################### local settings"                               >> $SERVER_PROPERTIES
echo "listeners=LISTENER_EXT://0.0.0.0:9092,LISTENER_INT://0.0.0.0:9093"        >> $SERVER_PROPERTIES
echo "advertised.listeners=LISTENER_EXT://$KAFKA_HOST:9092,LISTENER_INT://$KAFKA_HOST:9093" >> $SERVER_PROPERTIES
echo "listener.security.protocol.map=$KAFKA_LISTENER_SECURITY_PROTOCOL_MAP"     >> $SERVER_PROPERTIES
echo "inter.broker.listener.name=LISTENER_INT"                                  >> $SERVER_PROPERTIES

if [ -z "$SECURITY_PROTOCOL" || "$SECURITY_PROTOCOL" == "PLAINTEXT"  ]; then
  echo "Configure PLAINTEXT settings"
  echo "listener.security.protocol.map=LISTENER_EXT:PLAINTEXT,LISTENER_INT:PLAINTEXT"     >> $SERVER_PROPERTIES


elif [ "$SECURITY_PROTOCOL" == "SSL" ]; then
  echo "Configure SSL settings"
  echo "listener.security.protocol.map=LISTENER_EXT:SSL,LISTENER_INT:PLAINTEXT"     >> $SERVER_PROPERTIES

  export SSL_CONFIG_DIR=/tmp/kafka_ssl
  export CLIENT_KEYSTOREFILE=$SSL_CONFIG_DIR/kafka.client.keystore.p12
  export SERVER_KEYSTOREFILE=$SSL_CONFIG_DIR/kafka.server.keystore.p12
  export CLIENT_TRUSTSTOREFILE=$SSL_CONFIG_DIR/kafka.client.truststore.jks
  export SERVER_TRUSTSTOREFILE=$SSL_CONFIG_DIR/kafka.server.truststore.jks
  export CLIENT_PROPERTIES=$SSL_CONFIG_DIR/client.properties

  mkdir -p $SSL_CONFIG_DIR
  rm -f $SSL_CONFIG_DIR/*

  # Generate keystore
  keytool -keystore $SERVER_KEYSTOREFILE -alias localhost -validity 10000 -genkey -keyalg RSA -storetype pkcs12 -dname "CN=$KAFKA_HOST, OU=Unknown, O=Unknown, L=Unknown, ST=Unknown, C=DE" -storepass hugo01 -keypass hugo01
  # Disable hostname verification
  echo "ssl.endpoint.identification.algorithm=" >> $SERVER_PROPERTIES
  # Create your own CA (certificate authority)
  openssl req -new -x509 -keyout ca-key -out ca-cert -days 10000 -subj "/C=DE/ST=State/L=City/O=Organization/OU=Organizational Unit/CN=Common Name" -passin pass:hugo01 -passout pass:hugo01
  # Add the generated CA to the clients’ trust store so that the clients can trust this CA.
  keytool -keystore $SERVER_TRUSTSTOREFILE -alias CARoot -import -file ca-cert -storepass hugo01 -noprompt
  keytool -keystore $CLIENT_TRUSTSTOREFILE -alias CARoot -import -file ca-cert -storepass hugo01 -noprompt
  # Sign all certificates in the keystore with the CA generated.
  keytool -keystore $SERVER_KEYSTOREFILE -alias localhost -certreq -file cert-file -storepass hugo01
  # Sign it with CA
  openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file -out cert-signed -days 365 -CAcreateserial -passin pass:hugo01
  # Import both the certificates of the CA and the signed certificate into the keystore
  keytool -keystore $SERVER_KEYSTOREFILE -alias CARoot -import -file ca-cert -storepass hugo01 -noprompt
  keytool -keystore $SERVER_KEYSTOREFILE -alias localhost -import -file cert-signed -storepass hugo01 -noprompt
  # Create client keystore and import both certificates of the CA and signed certificates to client keystore. These client certificates will be used in application properties.
  keytool -keystore $CLIENT_KEYSTOREFILE -alias localhost -validity 365 -genkey -keyalg RSA -storetype pkcs12 -dname "CN=localhost, OU=Unknown, O=Unknown, L=Unknown, ST=Unknown, C=DE" -storepass hugo01 -keypass hugo01
  keytool -keystore $CLIENT_KEYSTOREFILE -alias localhost -certreq -file cert-file -storepass hugo01
  openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file -out cert-signed -days 365 -CAcreateserial -passin pass:hugo01
  keytool -keystore $CLIENT_KEYSTOREFILE -alias CARoot -import -file ca-cert -storepass hugo01 -noprompt
  keytool -keystore $CLIENT_KEYSTOREFILE -alias localhost -import -file cert-signed -storepass hugo01 -noprompt

  echo "ssl.keystore.location=$SERVER_KEYSTOREFILE"                               >> $SERVER_PROPERTIES
  echo "ssl.keystore.password=hugo01"                                             >> $SERVER_PROPERTIES
  echo "ssl.key.password=hugo01"                                                  >> $SERVER_PROPERTIES
  echo "ssl.keystore.type=PKCS12"                                                 >> $SERVER_PROPERTIES
  echo "ssl.truststore.location=$SERVER_TRUSTSTOREFILE"                           >> $SERVER_PROPERTIES
  echo "ssl.truststore.password=hugo01"                                           >> $SERVER_PROPERTIES
  echo "ssl.client.auth=required"                                                 >> $SERVER_PROPERTIES

  echo "Build client properties"
  echo "security.protocol=SSL"                                                     >  $CLIENT_PROPERTIES
  echo "ssl.truststore.location=$CLIENT_TRUSTSTOREFILE"                            >> $CLIENT_PROPERTIES
  echo "ssl.truststore.password=hugo01"                                            >> $CLIENT_PROPERTIES
  echo "ssl.keystore.location=$CLIENT_KEYSTOREFILE"                                >> $CLIENT_PROPERTIES
  echo "ssl.keystore.password=hugo01"                                              >> $CLIENT_PROPERTIES
  echo "ssl.key.password=hugo01"                                                   >> $CLIENT_PROPERTIES
  echo "ssl.keystore.type=PKCS12"                                                  >> $CLIENT_PROPERTIES
fi

/opt/kafka/bin/zookeeper-server-start.sh -daemon /opt/kafka/config/zookeeper.properties
/opt/kafka/bin/kafka-server-start.sh $SERVER_PROPERTIES
