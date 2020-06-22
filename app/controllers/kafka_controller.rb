class KafkaController < ApplicationController

  # read list of available topics from Kafka
  # GET kafka/topics
  def topics
    kafka = KafkaHelper.connect_kafka                                           # gets instance of class Kafka
    render json: { topics: kafka.topics}
  end

  # get info for topic from Kafka
  # GET kafka/describe_topic
  def describe_topic
    kafka = KafkaHelper.connect_kafka                                           # gets instance of class Kafka
    topic = params.permit(:topic)[:topic]
    configs = [
        'cleanup.policy', 'compression.type', 'delete.retention.ms', 'file.delete.delay.ms', 'flush.messages', 'flush.ms', 'follower.replication.throttled.replicas',
        'index.interval.bytes', 'leader.replication.throttled.replicas', 'max.compaction.lag.ms', 'max.message.bytes', 'message.format.version',
        'message.timestamp.difference.max.ms', 'message.timestamp.type', 'min.cleanable.dirty.ratio', 'min.compaction.lag.ms', 'min.insync.replicas',
        'preallocate', 'retention.bytes', 'retention.ms', 'segment.bytes', 'segment.index.bytes', 'segment.jitter.ms', 'segment.ms',
        'unclean.leader.election.enable', 'message.downconversion.enable'
    ]
    render json: kafka.describe_topic(topic, configs)
  end
end