# Run Kafka inside a docker container (docker in docker)
# Peter Ramm, 2020-03-07

function control_c {
    echo "SIGTERM catched"
  export TERMINATED=1
}
#trap control_c SIGINT
trap control_c SIGTERM

echo "Starting docker container for zookeeper"
docker run -d --net=host --name=zookeeper -e ZOOKEEPER_CLIENT_PORT=2181 -p 2181:2181 confluentinc/cp-zookeeper
echo $?

echo "Starting docker container for kafka"
docker run -d --net=host --name=kafka -e KAFKA_ZOOKEEPER_CONNECT=localhost:2181 \
              -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://localhost:9092 -e KAFKA_BROKER_ID=2 \
              -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 -p 9092:9092 confluentinc/cp-kafka
echo $?
docker ps


# wait until SIGTERM
export TERMINATED=0
while [ $TERMINATED -eq 0 ]
do
  sleep 1
done

echo "Terminated, shudown kafka and zookeeper"
docker stop kafka
docker stop zookeeper

echo "Remove container from parent docker engine"
docker rm kafka
docker rm zookeeper

