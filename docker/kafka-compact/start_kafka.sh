# Start the Kafka service inside the docker container
# Evaluate the SECURITY_PROTOCOL environment variable
# Store SSL config in /opt/kafka_ssl to mount it into the container

echo "KAFKA_VERSION = $KAFKA_VERSION"
echo "SCALA_VERSION = $SCALA_VERSION"
sed -i "s|^broker.id=.*$|broker.id=$BROKER_ID|" /opt/kafka/config/server.properties
echo "########################### local settings"                               >> /opt/kafka/config/server.properties
echo "listeners=$KAFKA_LISTENERS"                                               >> /opt/kafka/config/server.properties
echo "advertised.listeners=$KAFKA_ADVERTISED_LISTENERS"                         >> /opt/kafka/config/server.properties
echo "listener.security.protocol.map=$KAFKA_LISTENER_SECURITY_PROTOCOL_MAP"     >> /opt/kafka/config/server.properties
echo "inter.broker.listener.name=$KAFKA_INTER_BROKER_LISTENER_NAME"             >> /opt/kafka/config/server.properties

if [ "$SECURITY_PROTOCOL" == "SSL" ]; then
  export CLIENT_KEYSTOREFILE=/opt/kafka_ssl/kafka.client.keystore.p12
  export SERVER_KEYSTOREFILE=/opt/kafka_ssl/kafka.server.keystore.p12
  export CLIENT_TRUSTSTOREFILE=/opt/kafka_ssl/kafka.client.truststore.jks
  export SERVER_TRUSTSTOREFILE=/opt/kafka_ssk/kafka.server.truststore.jks
  export CLIENT_PROPERTIES=/opt/kafka_ssl/client.properties
  export SERVER_PROPERTIES=/opt/kafka_ssl/my_server.properties

# Generate keystore
keytool -keystore $SERVER_KEYSTOREFILE -alias localhost -validity 10000 -genkey -keyalg RSA -storetype pkcs12 -dname "CN=localhost, OU=Unknown, O=Unknown, L=Unknown, ST=Unknown, C=DE" -storepass hugo01 -keypass hugo01
# Disable hostname verification
echo "ssl.endpoint.identification.algorithm=" >> $KAFKA_HOME/config/server.properties
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


echo "listeners=$KAFKA_LISTENERS"                                               >> $SERVER_PROPERTIES
echo "advertised.listeners=$KAFKA_ADVERTISED_LISTENERS"                         >> $SERVER_PROPERTIES
echo "listener.security.protocol.map=$KAFKA_LISTENER_SECURITY_PROTOCOL_MAP"     >> $SERVER_PROPERTIES
echo "inter.broker.listener.name=$KAFKA_INTER_BROKER_LISTENER_NAME"             >> $SERVER_PROPERTIES

echo "ssl.keystore.location=$SERVER_KEYSTOREFILE"                               >> $SERVER_PROPERTIES
echo "ssl.keystore.password=hugo01"                                             >> $SERVER_PROPERTIES
echo "ssl.key.password=hugo01"                                                  >> $SERVER_PROPERTIES
echo "ssl.truststore.location=$SERVER_TRUSTSTOREFILE"                           >> $SERVER_PROPERTIES
echo "ssl.truststore.password=hugo01"                                           >> $SERVER_PROPERTIES

echo "Build client properties"
echo "security.protocol=SSL"                                                     >  $CLIENT_PROPERTIES
echo "ssl.truststore.location=$CLIENT_TRUSTSTOREFILE"                            >> $CLIENT_PROPERTIES
echo "ssl.truststore.password=hugo01"                                            >> $CLIENT_PROPERTIES
echo "ssl.keystore.location=$CLIENT_KEYSTOREFILE"                                >> $CLIENT_PROPERTIES
echo "ssl.keystore.password=hugo01"                                              >> $CLIENT_PROPERTIES
echo "ssl.key.password=hugo01"                                                   >> $CLIENT_PROPERTIES


fi

/opt/kafka/bin/zookeeper-server-start.sh -daemon /opt/kafka/config/zookeeper.properties
/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties