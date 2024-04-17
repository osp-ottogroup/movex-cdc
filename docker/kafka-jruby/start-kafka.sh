#!/bin/bash
# start Kafka inside a docker container
# part of Docker CMD or individual start in CI pipeline
# Peter Ramm, 2020-03-17

if [ -z "$SECURITY_PROTOCOL" ]; then
  echo "No SECURITY_PROTOCOL set, using PLAINTEXT"
  export SECURITY_PROTOCOL=PLAINTEXT
else
  echo "Using SECURITY_PROTOCOL = $SECURITY_PROTOCOL"
fi

export KAFKA_HOME=/opt/kafka
export BROKER_ID=-1
export WAIT_FOR_KAFKA_SECS=60
export CLIENT_KEYSTOREFILE=/opt/kafka/kafka.client.keystore.p12
export SERVER_KEYSTOREFILE=/opt/kafka/kafka.server.keystore.p12
export CLIENT_TRUSTSTOREFILE=/opt/kafka/kafka.client.truststore.jks
export SERVER_TRUSTSTOREFILE=/opt/kafka/kafka.server.truststore.jks
export CLIENT_PROPERTIES=/opt/kafka/client.properties
export SERVER_PROPERTIES=/opt/kafka/my_server.properties
export IP_ADDRESS=`ping -c 1 $HOSTNAME | awk -F'[()]' '/PING/{print $2}'`
echo "IP address of host = $IP_ADDRESS"
echo "Prepare configuration"
# Create a new server.properties file
cp -f $KAFKA_HOME/config/server.properties $SERVER_PROPERTIES
# Create a new client.properties file
rm -f $CLIENT_PROPERTIES
touch $CLIENT_PROPERTIES

sed -i "s|^broker.id=.*$|broker.id=$BROKER_ID|" $KAFKA_HOME/config/server.properties
echo "listeners=LISTENER_EXT://0.0.0.0:9092,LISTENER_INT://0.0.0.0:9093"                      >> $SERVER_PROPERTIES
echo "advertised.listeners=LISTENER_EXT://$IP_ADDRESS:9092,LISTENER_INT://localhost:9093"       >> $SERVER_PROPERTIES
echo "listener.security.protocol.map=LISTENER_EXT:$SECURITY_PROTOCOL,LISTENER_INT:PLAINTEXT"  >> $SERVER_PROPERTIES
echo "inter.broker.listener.name=LISTENER_INT"                                                >> $SERVER_PROPERTIES

if [ "$SECURITY_PROTOCOL" == "PLAINTEXT" ]; then
  echo "Nothing to do for PLAINTEXT"
elif [ "$SECURITY_PROTOCOL" == "SSL" ]; then
  # remove old ssl files if they exist
  rm -f $CLIENT_KEYSTOREFILE $SERVER_KEYSTOREFILE $CLIENT_TRUSTSTOREFILE $SERVER_TRUSTSTOREFILE
  # Generate keystore
  keytool -keystore $SERVER_KEYSTOREFILE -alias localhost -validity 10000 -genkey -keyalg RSA -storetype pkcs12 -dname "CN=localhost, OU=Unknown, O=Unknown, L=Unknown, ST=Unknown, C=DE" -storepass hugo01 -keypass hugo01
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
  echo "ssl.truststore.location=$SERVER_TRUSTSTOREFILE"                           >> $SERVER_PROPERTIES
  echo "ssl.truststore.password=hugo01"                                           >> $SERVER_PROPERTIES
  echo "ssl.client.auth=required"                                                 >> $SERVER_PROPERTIES

  echo "Build client properties"
  echo "security.protocol=SSL"                                                     >> $CLIENT_PROPERTIES
  echo "ssl.truststore.location=$CLIENT_TRUSTSTOREFILE"                            >> $CLIENT_PROPERTIES
  echo "ssl.truststore.password=hugo01"                                            >> $CLIENT_PROPERTIES
  echo "ssl.keystore.location=$CLIENT_KEYSTOREFILE"                                >> $CLIENT_PROPERTIES
  echo "ssl.keystore.password=hugo01"                                              >> $CLIENT_PROPERTIES
  echo "ssl.key.password=hugo01"                                                   >> $CLIENT_PROPERTIES
else
  echo "Unsupported SECURITY_PROTOCOL = $SECURITY_PROTOCOL"
  exit 1
fi

echo "Starting Zookeeper"
$KAFKA_HOME/bin/zookeeper-server-start.sh -daemon $KAFKA_HOME/config/zookeeper.properties

echo "Starting Kafka"
$KAFKA_HOME/bin/kafka-server-start.sh     -daemon $SERVER_PROPERTIES

typeset -i LOOP_COUNT=0
KAFKA_STARTED="started (kafka.server.KafkaServer)"
echo "Wait for Kafka operation"
while [ 1 -eq 1 ]
do
  grep "$KAFKA_STARTED" $KAFKA_HOME/logs/kafkaServer.out >/dev/null
  if [ $? -eq 0 ]; then
    echo ""
    grep "$KAFKA_STARTED" $KAFKA_HOME/logs/kafkaServer.out
    echo "KAFKA_VERSION = $KAFKA_VERSION"
    echo "SCALA_VERSION = $SCALA_VERSION"
    echo "Creating topics and consumer groups"
    echo "Following double output 'org.apache.kafka.common.errors.TimeoutException' is 'works as designed'"
    $KAFKA_HOME/bin/kafka-topics.sh --create --topic TestTopic1 --partitions 4 --bootstrap-server localhost:9092 --replication-factor 1 --command-config $CLIENT_PROPERTIES
    $KAFKA_HOME/bin/kafka-topics.sh --create --topic TestTopic2 --partitions 8 --bootstrap-server localhost:9092 --replication-factor 1 --command-config $CLIENT_PROPERTIES
    echo "Waiting for Kafka to create groups now"
    $KAFKA_HOME/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic TestTopic1 --group Group1 --timeout-ms ${WAIT_FOR_KAFKA_SECS}000 --consumer.config $CLIENT_PROPERTIES &
    $KAFKA_HOME/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic TestTopic1 --group Group2 --timeout-ms ${WAIT_FOR_KAFKA_SECS}000 --consumer.config $CLIENT_PROPERTIES &
    typeset -i GROUP_LOOP_COUNT=0
    while [ 1 -eq 1 ]
    do
      GROUP_COUNT=`$KAFKA_HOME/bin/kafka-consumer-groups.sh --bootstrap-server=localhost:9092 --list --command-config $CLIENT_PROPERTIES | wc -l`
      if [ $GROUP_COUNT -eq 2 ]; then
        echo "Kafka has two groups now"
        $KAFKA_HOME/bin/kafka-consumer-groups.sh --bootstrap-server=localhost:9092 --list --command-config $CLIENT_PROPERTIES
        exit 0
      fi
      GROUP_LOOP_COUNT=$GROUP_LOOP_COUNT+1
      if [ $GROUP_LOOP_COUNT -gt $WAIT_FOR_KAFKA_SECS ]; then
        echo "Two Kafka groups missing after $WAIT_FOR_KAFKA_SECS seconds, terminating"
        $KAFKA_HOME/bin/kafka-consumer-groups.sh --bootstrap-server=localhost:9092 --list --command-config $CLIENT_PROPERTIES
        exit 1
      fi
      echo -n "."
      sleep 1
    done
  fi

  LOOP_COUNT=$LOOP_COUNT+1
  if [ $LOOP_COUNT -gt $WAIT_FOR_KAFKA_SECS ]; then
    echo ""
    echo "Kafka not in operation after $WAIT_FOR_KAFKA_SECS seconds, terminating"
    echo ""
    echo "############# Zookeeper log ##############"
    cat $KAFKA_HOME/logs/zookeeper.out
    echo ""
    echo "############# Kafka log ##############"
    cat $KAFKA_HOME/logs/kafkaServer.out
    exit 1
  fi
  echo -n "."
  sleep 1
done



