module KafkaHelper

  @@existing_topic_for_test = nil
  # get name of existing topic and cache for lifetime
  def self.existing_topic_for_test
    if @@existing_topic_for_test.nil?
      topics = KafkaBase.create.topics
      raise "No topic configured yet at Kafka" if topics.length == 0
      test_topics = topics.select {|t| !t['__']}                                # discard all topics with '__' like '__consumer_offsets', '__transaction_state' etc.
      @@existing_topic_for_test = test_topics[0]                                # use first remaining topic as sample
    end
    @@existing_topic_for_test
  end

  @@existing_group_id_for_test = nil
  # get name of existing group and cache for lifetime
  def self.existing_group_id_for_test
    if @@existing_group_id_for_test.nil?
      groups = KafkaBase.create.groups
      raise "No consumer group configured yet at Kafka" if groups.length == 0
      @@existing_group_id_for_test = groups[0]                                  # use first existing group as sample
    end
    @@existing_group_id_for_test
  end

end