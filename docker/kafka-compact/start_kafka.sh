# Start the Kafka service inside the docker container
# Evaluate the SECURITY_PROTOCOL environment variable

echo "KAFKA_VERSION = $KAFKA_VERSION"
echo "SCALA_VERSION = $SCALA_VERSION"
sed -i "s|^broker.id=.*$|broker.id=$BROKER_ID|" /opt/kafka/config/server.properties
echo "########################### local settings"                               >> /opt/kafka/config/server.properties
echo "listeners=$KAFKA_LISTENERS"                                               >> /opt/kafka/config/server.properties
echo "advertised.listeners=$KAFKA_ADVERTISED_LISTENERS"                         >> /opt/kafka/config/server.properties
echo "listener.security.protocol.map=$KAFKA_LISTENER_SECURITY_PROTOCOL_MAP"     >> /opt/kafka/config/server.properties
echo "inter.broker.listener.name=$KAFKA_INTER_BROKER_LISTENER_NAME"             >> /opt/kafka/config/server.properties
/opt/kafka/bin/zookeeper-server-start.sh -daemon /opt/kafka/config/zookeeper.properties
/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties