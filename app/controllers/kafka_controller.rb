class KafkaController < ApplicationController

  # read list of available topics from Kafka
  # GET kafka/topics
  def topics
    render json: { topics: KafkaBase.create.topics.sort}
  end

  # get info for topic from Kafka
  # GET kafka/describe_topic
  def describe_topic
    topic   = params.permit(:topic)[:topic]
    render json: KafkaBase.create.describe_topic_complete(topic)
  end

  # Check if topic exists
  # GET kafka/has_topic
  def has_topic
    topic = params.permit(:topic)[:topic]
    render json: { has_topic: KafkaBase.create.has_topic?(topic)}
  end

  # list existing consumer groups
  # GET kafka/groups
  def groups
    render json: { groups: KafkaBase.create.groups.sort}
  end

  # get info about a group by group_id
  # GET kafka/describe_group
  def describe_group
    group_id = params.permit(:group_id)[:group_id]
    render json: KafkaBase.create.describe_group(group_id)
  end

end
