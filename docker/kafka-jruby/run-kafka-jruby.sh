#!/bin/bash
# Run Kafka inside a docker container without external access
# Peter Ramm, 2020-03-17

function control_c {
  export TERMINATED=1
}
trap control_c SIGINT
trap control_c SIGTERM

/opt/start-kafka.sh

# wait until SIGTERM
export TERMINATED=0
while [ $TERMINATED -eq 0 ]
do
  sleep 1
done

echo "Container stopped, shutdown kafka"
/opt/kafka/bin/kafka-server-stop.sh


