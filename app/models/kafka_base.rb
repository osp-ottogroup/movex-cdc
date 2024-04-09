# Generic class for Kafka producers and service functions
class KafkaBase
  attr_reader :config

  # Error class for Kafka errors independent from used library
  class ConcurrentTransactionError < Exception
  end

  # Producer class with generic functions independent from used library
  class Producer
    attr_reader :max_message_bulk_count

    # @param kafka [KafkaBase] Kafka object inherited from KafkaBase
    # @param transactional_id [String] Transactional ID for Kafka producer
    def initialize(kafka, transactional_id:)
      @kafka                      = kafka
      @max_message_bulk_count     = MovexCdc::Application.config.kafka_max_bulk_count   # Keep this value for the lifetime of the producer, event if the config changes
      @max_buffer_bytesize        = (MovexCdc::Application.config.kafka_total_buffer_size_mb * 1024 * 1024).to_i
      @transactional_id           = transactional_id
      @topic_infos                = {}                                          # Max message size produced within a transaction so far per topic
    end

    private
    # Reduce the number of messages in bulk if exception occurs
    def handle_kafka_buffer_overflow(exception, kafka_message, topic, table)
      Rails.logger.warn "#{exception.class} #{exception.message}: max_buffer_size = #{@max_message_bulk_count}, max_buffer_bytesize = #{@max_buffer_bytesize}, current message value size = #{kafka_message.bytesize}, topic = #{topic}, schema = #{table.schema.name}, table = #{table.name}"
      if kafka_message.bytesize > @max_buffer_bytesize / 3
        Rails.logger.error('TransferThread.handle_kafka_buffer_overflow'){"Single message size exceeds 1/3 of the Kafka buffer size! No automatic action called! Possibly increase KAFKA_TOTAL_BUFFER_SIZE_MB to fix this issue."}
      else
        reduce_step = @max_message_bulk_count / 10                  # Reduce by 10%
        if @max_message_bulk_count > reduce_step + 1
          @max_message_bulk_count -= reduce_step
          MovexCdc::Application.config.kafka_max_bulk_count = @max_message_bulk_count  # Ensure reduced value is valid also for new TransferThreads
          Rails.logger.warn "Reduce max_message_bulk_count by #{reduce_step} to #{@max_message_bulk_count} to prevent this situation"
        end
      end
    end

    # fix Exception Kafka::MessageSizeTooLarge
    # enlarge Topic property "max.message.bytes" to needed value
    def fix_message_size_too_large
      if @topic_infos.count != 1
        Rails.logger.warn('KafkaRuby::Producer.fix_message_size_too_large') { "There are #{@topic_infos.count} topics included in the transaction. Fix of max.message.bytes suspended until divide&conquer ensures that transaction contains only one topic" }
      else
        # get current max.message.byte per topic
        @topic_infos.each do |key, value|                                       # should be only one topic, but does nothing if there is none
          current_max_message_bytes = @kafka.describe_topic_attr(key, 'max.message.bytes').to_i
          Rails.logger.warn('KafkaRuby::Producer.fix_message_size_too_large') { "Messages for topic '#{key}' have max. size per message of #{value[:max_produced_message_size]} bytes for transfer, topic-config max.message.bytes = #{current_max_message_bytes}" }

          if current_max_message_bytes && value[:max_produced_message_size] > current_max_message_bytes * 0.5
            # new max.message.bytes based on current value or largest msg size, depending on the larger one
            new_max_message_bytes = value[:max_produced_message_size]
            new_max_message_bytes = current_max_message_bytes if current_max_message_bytes > new_max_message_bytes
            new_max_message_bytes = (new_max_message_bytes * 1.2).to_i              # Enlarge by 20%

            response = @kafka.alter_topic(key, "max.message.bytes" => new_max_message_bytes.to_s)
            unless response.nil?
              Rails.logger.error('KafkaBase::Producer.fix_message_size_too_large') { alter topic "#{response.class} #{response}:" }
            else
              Rails.logger.warn('KafkaBase::Producer.fix_message_size_too_large') { "Enlarge max.message.bytes for topic #{key} from #{current_max_message_bytes} to #{new_max_message_bytes} to prevent Kafka::MessageSizeTooLarge" }
            end
          else
            Rails.logger.warn('KafkaBase::Producer.fix_message_size_too_large') { "No action raised because size of largest message is less than half of max.message.bytes" }
          end
        rescue Exception => e
          Rails.logger.error('KafkaBase::Producer.fix_message_size_too_large') { "#{e.class}: #{e.message} while getting or setting topic property max.message.bytes" }
        end
      end
    end
  end # class Producer

  # Factory method to create a Kafka producer object
  # @return [KafkaBase] Kafka producer object of derived class
  def self.create
    case MovexCdc::Application.config.kafka_client_library
    when 'java' then KafkaJava.new
    when 'ruby' then KafkaRuby.new
    when 'mock' then KafkaMock.new
    else raise "Unsupported value '#{MovexCdc::Application.config.kafka_client_library}' for KAFKA_CLIENT_LIBRARY"
    end
  end

  # @param topic [String] Kafka topic name to check for existence
  # @return [Boolean] True if the topic exists
  def has_topic?(topic)
    topics.include?(topic)
  end

  # @param topic [String] Kafka group id to check for existence
  # @return [Boolean] True if the group exists
  def has_group?(group_id)
    groups.include?(group_id)
  end

  # @return [Hash] topic configuration items
  def topic_attributes_for_describe
    # Available config items according to: https://docs.confluent.io/platform/current/installation/configuration/topic-configs.html
    {
      'cleanup.policy'              => { info: 'A string that is either "delete" or "compact" or both. This string designates the retention policy to use on old log segments. The default policy ("delete") will discard old segments when their retention time or size limit has been reached. The "compact" setting will enable log compaction on the topic.'},
      'compression.type'            => { info: "Specify the final compression type for a given topic. This configuration accepts the standard compression codecs ('gzip', 'snappy', 'lz4', 'zstd'). It additionally accepts 'uncompressed' which is equivalent to no compression; and 'producer' which means retain the original compression codec set by the producer."},
      'confluent.cluster.link.allow.legacy.message.format' => { info: "Whether or not to allow mirroring v0/v1 messages into the topic"},
      'confluent.key.schema.validation' => { info: "True if schema validation at record key is enabled for this topic."},
      'confluent.key.subject.name.strategy' => { info: "Determines how to construct the subject name under which the key schema is registered with the schema registry. By default, TopicNameStrategy is used"},
      'confluent.placement.constraints' => { info: "This configuration is a JSON object that controls the set of brokers (replicas) which will always be allowed to join the ISR. And the set of brokers (observers) which are not allowed to join the ISR. The format of JSON is:{ “version”: 1, “replicas”: [ { “count”: 2, “constraints”: {“rack”: “east-1”} }, { “count”: 1, “constraints”: {“rack”: “east-2”} } ], “observers”:[ { “count”: 1, “constraints”: {“rack”: “west-1”} } ]}"},
      'confluent.tier.enable'        => { info: "Allow tiering for topic(s). This enables tiering and fetching of data to and from the configured remote storage. When set to true, this causes all existing, non-compacted topics to also have this configuration set to true. Only topics explicitly set to false will remain false.It is not required to set confluent.tier.enable=true to enable Tiered Storage."},
      'confluent.tier.local.hotset.bytes' => { info: "When tiering is enabled, this configuration controls the maximum size a partition (which consists of log segments) can grow to on broker-local storage before we will discard old log segments to free up space. Log segments retained on broker-local storage is referred as the “hotset”. Segments discarded from local store could continue to exist in tiered storage and remain available for fetches depending on retention configurations. By default there is no size limit only a time limit. Since this limit is enforced at the partition level, multiply it by the number of partitions to compute the topic hotset in bytes."},
      'confluent.tier.local.hotset.ms' => { info: "When tiering is enabled, this configuration controls the maximum time we will retain a log segment on broker-local storage before we will discard it to free up space. Segments discarded from local store could continue to exist in tiered storage and remain available for fetches depending on retention configurations. If set to -1, no time limit is applied."},
      'confluent.value.schema.validation' => { info: "True if schema validation at record value is enabled for this topic."},
      'confluent.value.subject.name.strategy' => { info: "Determines how to construct the subject name under which the value schema is registered with the schema registry. By default, TopicNameStrategy is used"},
      'delete.retention.ms'         => { info: 'The amount of time to retain delete tombstone markers for log compacted topics. This setting also gives a bound on the time in which a consumer must complete a read if they begin from offset 0 to ensure that they get a valid snapshot of the final stage (otherwise delete tombstones may be collected before they complete their scan).'},
      'file.delete.delay.ms'        => { info: 'The time to wait before deleting a file from the filesystem'},
      'flush.messages'              => { info: "This setting allows specifying an interval at which we will force an fsync of data written to the log. For example if this was set to 1 we would fsync after every message; if it were 5 we would fsync after every five messages. In general we recommend you not set this and use replication for durability and allow the operating system's background flush capabilities as it is more efficient. This setting can be overridden on a per-topic basis (see the per-topic configuration section)."},
      'flush.ms'                    => { info: "This setting allows specifying a time interval at which we will force an fsync of data written to the log. For example if this was set to 1000 we would fsync after 1000 ms had passed. In general we recommend you not set this and use replication for durability and allow the operating system's background flush capabilities as it is more efficient."},
      'follower.replication.throttled.replicas'=> { info: "A list of replicas for which log replication should be throttled on the follower side. The list should describe a set of replicas in the form [PartitionId]:[BrokerId],[PartitionId]:[BrokerId]:... or alternatively the wildcard '*' can be used to throttle all replicas for this topic."},
      'index.interval.bytes'        => { info: "This setting controls how frequently Kafka adds an index entry to its offset index. The default setting ensures that we index a message roughly every 4096 bytes. More indexing allows reads to jump closer to the exact position in the log but makes the index larger. You probably don't need to change this."},
      'leader.replication.throttled.replicas'=> { info: "A list of replicas for which log replication should be throttled on the leader side. The list should describe a set of replicas in the form [PartitionId]:[BrokerId],[PartitionId]:[BrokerId]:... or alternatively the wildcard '*' can be used to throttle all replicas for this topic."},
      'local.retention.bytes'       => { info: "The maximum size of local log segments that can grow for a partition before it deletes the old segments. Default value is -2, it represents retention.bytes value to be used. The effective value should always be less than or equal to retention.bytes value."},
      'local.retention.ms'          => { info: "The number of milli seconds to keep the local log segment before it gets deleted. Default value is -2, it represents retention.ms value is to be used. The effective value should always be less than or equal to retention.ms value."},
      'max.compaction.lag.ms'       => { info: "The maximum time a message will remain ineligible for compaction in the log. Only applicable for logs that are being compacted."},
      'max.message.bytes'           => { info: "The largest record batch size allowed by Kafka (after compression if compression is enabled). If this is increased and there are consumers older than 0.10.2, the consumers' fetch size must also be increased so that they can fetch record batches this large. In the latest message format version, records are always grouped into batches for efficiency. In previous message format versions, uncompressed records are not grouped into batches and this limit only applies to a single record in that case."},
      'message.downconversion.enable'=> { info: "This configuration controls whether down-conversion of message formats is enabled to satisfy consume requests. When set to false, broker will not perform down-conversion for consumers expecting an older message format. The broker responds with UNSUPPORTED_VERSION error for consume requests from such older clients. This configurationdoes not apply to any message format conversion that might be required for replication to followers."},
      'message.format.version'      => { info: "[DEPRECATED] Specify the message format version the broker will use to append messages to the logs. The value of this config is always assumed to be `3.0` if `inter.broker.protocol.version` is 3.0 or higher (the actual config value is ignored). Otherwise, the value should be a valid ApiVersion. Some examples are: 0.10.0, 1.1, 2.8, 3.0. By setting a particular message format version, the user is certifying that all the existing messages on disk are smaller or equal than the specified version. Setting this value incorrectly will cause consumers with older versions to break as they will receive messages with a format that they don't understand."},
      'message.timestamp.after.max.ms' => { info: "This configuration sets the allowable timestamp difference between the message timestamp and the broker’s timestamp. The message timestamp can be later than or equal to the broker’s timestamp, with the maximum allowable difference determined by the value set in this configuration. If message.timestamp.type=CreateTime, the message will be rejected if the difference in timestamps exceeds this specified threshold. This configuration is ignored if message.timestamp.type=LogAppendTime."},
      'message.timestamp.before.max.ms' => { info: "This configuration sets the allowable timestamp difference between the broker’s timestamp and the message timestamp. The message timestamp can be earlier than or equal to the broker’s timestamp, with the maximum allowable difference determined by the value set in this configuration. If message.timestamp.type=CreateTime, the message will be rejected if the difference in timestamps exceeds this specified threshold. This configuration is ignored if message.timestamp.type=LogAppendTime."},
      'message.timestamp.difference.max.ms'=> { info: "The maximum difference allowed between the timestamp when a broker receives a message and the timestamp specified in the message. If message.timestamp.type=CreateTime, a message will be rejected if the difference in timestamp exceeds this threshold. This configuration is ignored if message.timestamp.type=LogAppendTime."},
      'message.timestamp.type'      => { info: "Define whether the timestamp in the message is message create time or log append time. The value should be either `CreateTime` or `LogAppendTime`"},
      'min.cleanable.dirty.ratio'   => { info: "This configuration controls how frequently the log compactor will attempt to clean the log (assuming log compaction is enabled). By default we will avoid cleaning a log where more than 50% of the log has been compacted. This ratio bounds the maximum space wasted in the log by duplicates (at 50% at most 50% of the log could be duplicates). A higher ratio will mean fewer, more efficient cleanings but will mean more wasted space in the log. If the max.compaction.lag.ms or the min.compaction.lag.ms configurations are also specified, then the log compactor considers the log to be eligible for compaction as soon as either: (i) the dirty ratio threshold has been met and the log has had dirty (uncompacted) records for at least the min.compaction.lag.ms duration, or (ii) if the log has had dirty (uncompacted) records for at most the max.compaction.lag.ms period."},
      'min.compaction.lag.ms'       => { info: "The minimum time a message will remain uncompacted in the log. Only applicable for logs that are being compacted."},
      'min.insync.replicas'         => { info: "When a producer sets acks to 'all' (or '-1'), this configuration specifies the minimum number of replicas that must acknowledge a write for the write to be considered successful. If this minimum cannot be met, then the producer will raise an exception (either NotEnoughReplicas or NotEnoughReplicasAfterAppend). When used together, min.insync.replicas and acks allow you to enforce greater durability guarantees. A typical scenario would be to create a topic with a replication factor of 3, set min.insync.replicas to 2, and produce with acks of 'all'. This will ensure that the producer raises an exception if a majority of replicas do not receive a write."},
      'preallocate'                 => { info: "True if we should preallocate the file on disk when creating a new log segment."},
      'remote.storage.enabled'      => { info: "To enable tiered storage for a topic, set this configuration as true. You can not disable this config once it is enabled. It will be provided in future versions."},
      'retention.bytes'             => { info: "This configuration controls the maximum size a partition (which consists of log segments) can grow to before we will discard old log segments to free up space if we are using the 'delete' retention policy. By default there is no size limit only a time limit. Since this limit is enforced at the partition level, multiply it by the number of partitions to compute the topic retention in bytes."},
      'retention.ms'                => { info: "This configuration controls the maximum time we will retain a log before we will discard old log segments to free up space if we are using the 'delete' retention policy. This represents an SLA on how soon consumers must read their data. If set to -1, no time limit is applied."},
      'segment.bytes'               => { info: "This configuration controls the segment file size for the log. Retention and cleaning is always done a file at a time so a larger segment size means fewer files but less granular control over retention."},
      'segment.index.bytes'         => { info: "This configuration controls the size of the index that maps offsets to file positions. We preallocate this index file and shrink it only after log rolls. You generally should not need to change this setting."},
      'segment.jitter.ms'           => { info: "The maximum random jitter subtracted from the scheduled segment roll time to avoid thundering herds of segment rolling"},
      'segment.ms'                  => { info: "This configuration controls the period of time after which Kafka will force the log to roll even if the segment file isn't full to ensure that retention can delete or compact old data."},
      'unclean.leader.election.enable'=> { info: "Indicates whether to enable replicas not in the ISR set to be elected as leader as a last resort, even though doing so may result in data loss."},
    }.clone
  end

  private
  def initialize
    @config = {}
    @config[:client_id]                     =  "MOVEX-CDC-#{Socket.gethostname}"
  end
end