# Run kafka local

cd /Users/pramm/Documents/Projekte/gitlab.com/movex-cdc/docker/kafka-compact
docker rm -f kafka
docker build -f Dockerfile-kafka-compact -t registry.gitlab.com/osp-silver/oss/movex-cdc/kafka-compact:3.7.0 .
docker run -d -p 2181:2181 -p 9092:9092 --name kafka -e KAFKA_HOST_IP=192.168.178.34 -e SECURITY_PROTOCOL=SSL registry.gitlab.com/osp-silver/oss/movex-cdc/kafka-compact:3.7.0
echo "Waiting for SSL files"
sleep 5 
docker cp kafka:/tmp/kafka_ssl/client.properties /tmp/kafka_ssl
docker cp kafka:/tmp/kafka_ssl/kafka.client.keystore.p12 /tmp/kafka_ssl
docker cp kafka:/tmp/kafka_ssl/kafka.client.truststore.jks /tmp/kafka_ssl
