class KafkaController < ApplicationController

  # read list of available topics from Kafka
  # GET kafka/topics
  def topics
    kafka = KafkaHelper.connect_kafka                                           # gets instance of class Kafka
    render json: { topics: kafka.topics.sort}
  end

  # get info for topic from Kafka
  # GET kafka/describe_topic
  def describe_topic
    kafka   = KafkaHelper.connect_kafka                                         # gets instance of class Kafka
    topic   = params.permit(:topic)[:topic]
    cluster = kafka.instance_variable_get('@cluster')                           # possibly instable access on internal structures
    result = {}

    result[:partitions]   = kafka.partitions_for(topic)
    result[:replicas]     = kafka.replica_count_for(topic)
    result[:last_offsets] = kafka.last_offsets_for(topic)[topic]
    result[:leaders]      = {}
    0.upto(result[:partitions]-1) do |p|
      result[:leaders][p.to_s] = cluster.get_leader(topic, p).to_s
    rescue Exception => e
      result[:leaders][p.to_s] = "Exception: #{e.class}:#{e.message}"
    end
    configs = [
        'cleanup.policy', 'compression.type', 'delete.retention.ms', 'file.delete.delay.ms', 'flush.messages', 'flush.ms', 'follower.replication.throttled.replicas',
        'index.interval.bytes', 'leader.replication.throttled.replicas', 'max.compaction.lag.ms', 'max.message.bytes', 'message.format.version',
        'message.timestamp.difference.max.ms', 'message.timestamp.type', 'min.cleanable.dirty.ratio', 'min.compaction.lag.ms', 'min.insync.replicas',
        'preallocate', 'retention.bytes', 'retention.ms', 'segment.bytes', 'segment.index.bytes', 'segment.jitter.ms', 'segment.ms',
        'unclean.leader.election.enable', 'message.downconversion.enable'
    ]
    begin
      result[:config] = kafka.describe_topic(topic, configs)
    rescue Exception => e
      result[:config] = "Exception: #{e.class}:#{e.message}"
    end
    render json: result
  end

  # Check if topic exists
  # GET kafka/has_topic
  def has_topic
    topic = params.permit(:topic)[:topic]
    if KafkaHelper.has_topic?(topic)
      render json: { has_topic: true}
    else
      render json: { has_topic: false}
    end
  end

  # list existing consumer groups
  # GET kafka/groups
  def groups
    kafka = KafkaHelper.connect_kafka                                           # gets instance of class Kafka
    render json: { groups: kafka.groups.sort}
  end

  # get info about a group by group_id
  # GET kafka/describe_group
  def describe_group
    kafka = KafkaHelper.connect_kafka                                           # gets instance of class Kafka
    group_id = params.permit(:group_id)[:group_id]
    render json: kafka.describe_group(group_id)
  end

end
