#!/bin/bash
# start Kafka inside a docker container
# part of Docker CMD or individual start in CI pipeline
# Peter Ramm, 2020-03-17

export BROKER_ID=-1
export KAFKA_LISTENERS=LISTENER_EXT://0.0.0.0:9092,LISTENER_INT://0.0.0.0:9093
export KAFKA_ADVERTISED_LISTENERS=LISTENER_EXT://localhost:9092,LISTENER_INT://localhost:9093
export KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=LISTENER_EXT:PLAINTEXT,LISTENER_INT:PLAINTEXT
export KAFKA_INTER_BROKER_LISTENER_NAME=LISTENER_INT

echo "Prepare configuration"
sed -i "s|^broker.id=.*$|broker.id=$BROKER_ID|" /opt/kafka/config/server.properties
echo "listeners=$KAFKA_LISTENERS"                                               >> /opt/kafka/config/server.properties
echo "advertised.listeners=$KAFKA_ADVERTISED_LISTENERS"                         >> /opt/kafka/config/server.properties
echo "listener.security.protocol.map=$KAFKA_LISTENER_SECURITY_PROTOCOL_MAP"     >> /opt/kafka/config/server.properties
echo "inter.broker.listener.name=$KAFKA_INTER_BROKER_LISTENER_NAME"             >> /opt/kafka/config/server.properties

echo "Starting Zookeeper"
/opt/kafka/bin/zookeeper-server-start.sh -daemon /opt/kafka/config/zookeeper.properties

echo "Starting Kafka"
/opt/kafka/bin/kafka-server-start.sh     -daemon /opt/kafka/config/server.properties

typeset -i LOOP_COUNT=0
KAFKA_AVAIL=NO
echo "Wait for Kafka operation"
while [ "$KAFKA_AVAIL" == 'NO' ]
do
  grep "started (kafka.server.KafkaServer)" /opt/kafka/logs/kafkaServer.out >/dev/null
  if [ $? -eq 0 ]; then
    echo ""
    grep "started (kafka.server.KafkaServer)" /opt/kafka/logs/kafkaServer.out
    exit 0
  fi

  LOOP_COUNT=$LOOP_COUNT+1
  if [ $LOOP_COUNT -gt 10 ]; then
    echo "\nKafka not in operation after x seconds, terminating"
    echo ""
    echo "############# Zookeeper log ##############"
    cat /opt/kafka/logs/zookeeper.out
    echo ""
    echo "############# Kafka log ##############"
    cat /opt/kafka/logs/kafkaServer.out
    exit 1
  fi
  echo -n "."
  sleep 1
done



