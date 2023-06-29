# Generic class for Kafka producers and service functions
class KafkaBase
  attr_reader :config

  # Error class for Kafka errors independent from used library
  class ConcurrentTransactionError < Exception
  end

  # Producer class with generic functions independent from used library
  class Producer
    attr_reader :max_message_bulk_count
    def initialize(transactional_id:)
      @max_message_bulk_count     = MovexCdc::Application.config.kafka_max_bulk_count   # Keep this value for the lifetime of the producer, event if the config changes
      @max_buffer_bytesize        = MovexCdc::Application.config.kafka_total_buffer_size_mb * 1024 * 1024
      @transactional_id           = transactional_id
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
  end

  # Factory method to create a Kafka producer object
  # @return [KafkaBase] Kafka producer object of derived class
  def self.create
    if MovexCdc::Application.config.kafka_seed_broker == '/dev/null'
      KafkaMock.new(MovexCdc::Application.config.kafka_seed_broker, {})
    else
      KafkaRuby.new
    end
  end

  private
  def initialize
    @config = {}
    @config[:client_id]                     =  "MOVEX-CDC-#{Socket.gethostname}"
    @config[:seed_brokers]                  = MovexCdc::Application.config.kafka_seed_broker.split(',').map{|b| b.strip}
    @config[:ssl_ca_certs_from_system]      = true if MovexCdc::Application.config.kafka_ssl_ca_certs_from_system.is_a? (TrueClass) || MovexCdc::Application.config.kafka_ssl_ca_certs_from_system == 'TRUE'
    @config[:ssl_ca_cert_file_path]         = MovexCdc::Application.config.kafka_ssl_ca_cert.split(',').map{|s| s.strip}  if MovexCdc::Application.config.kafka_ssl_ca_cert
    @config[:ssl_client_cert_chain]         = File.read(MovexCdc::Application.config.kafka_ssl_client_cert_chain) if MovexCdc::Application.config.kafka_ssl_client_cert_chain
    @config[:ssl_client_cert]               = File.read(MovexCdc::Application.config.kafka_ssl_client_cert)       if MovexCdc::Application.config.kafka_ssl_client_cert
    @config[:ssl_client_cert_key]           = File.read(MovexCdc::Application.config.kafka_ssl_client_cert_key)   if MovexCdc::Application.config.kafka_ssl_client_cert_key
    @config[:ssl_client_cert_key_password]  = MovexCdc::Application.config.kafka_ssl_client_cert_key_password     if MovexCdc::Application.config.kafka_ssl_client_cert_key_password
    @config[:sasl_plain_username]           = MovexCdc::Application.config.kafka_sasl_plain_username if MovexCdc::Application.config.kafka_sasl_plain_username
    @config[:sasl_plain_password]           = MovexCdc::Application.config.kafka_sasl_plain_password if MovexCdc::Application.config.kafka_sasl_plain_password
  end

  public

  # @return [Hash] topic configuration items
  def topic_attributes_for_describe
    # Available config items according to: https://docs.confluent.io/platform/current/installation/configuration/topic-configs.html
    {
      'cleanup.policy'              => { info: 'A string that is either "delete" or "compact" or both. This string designates the retention policy to use on old log segments. The default policy ("delete") will discard old segments when their retention time or size limit has been reached. The "compact" setting will enable log compaction on the topic.'},
      'compression.type'            => { info: "Specify the final compression type for a given topic. This configuration accepts the standard compression codecs ('gzip', 'snappy', 'lz4', 'zstd'). It additionally accepts 'uncompressed' which is equivalent to no compression; and 'producer' which means retain the original compression codec set by the producer."},
      'delete.retention.ms'         => { info: 'The amount of time to retain delete tombstone markers for log compacted topics. This setting also gives a bound on the time in which a consumer must complete a read if they begin from offset 0 to ensure that they get a valid snapshot of the final stage (otherwise delete tombstones may be collected before they complete their scan).'},
      'file.delete.delay.ms'        => { info: 'The time to wait before deleting a file from the filesystem'},
      'flush.messages'              => { info: "This setting allows specifying an interval at which we will force an fsync of data written to the log. For example if this was set to 1 we would fsync after every message; if it were 5 we would fsync after every five messages. In general we recommend you not set this and use replication for durability and allow the operating system's background flush capabilities as it is more efficient. This setting can be overridden on a per-topic basis (see the per-topic configuration section)."},
      'flush.ms'                    => { info: "This setting allows specifying a time interval at which we will force an fsync of data written to the log. For example if this was set to 1000 we would fsync after 1000 ms had passed. In general we recommend you not set this and use replication for durability and allow the operating system's background flush capabilities as it is more efficient."},
      'follower.replication.throttled.replicas'=> { info: "A list of replicas for which log replication should be throttled on the follower side. The list should describe a set of replicas in the form [PartitionId]:[BrokerId],[PartitionId]:[BrokerId]:... or alternatively the wildcard '*' can be used to throttle all replicas for this topic."},
      'index.interval.bytes'        => { info: "This setting controls how frequently Kafka adds an index entry to its offset index. The default setting ensures that we index a message roughly every 4096 bytes. More indexing allows reads to jump closer to the exact position in the log but makes the index larger. You probably don't need to change this."},
      'leader.replication.throttled.replicas'=> { info: "A list of replicas for which log replication should be throttled on the leader side. The list should describe a set of replicas in the form [PartitionId]:[BrokerId],[PartitionId]:[BrokerId]:... or alternatively the wildcard '*' can be used to throttle all replicas for this topic."},
      'max.compaction.lag.ms'       => { info: "The maximum time a message will remain ineligible for compaction in the log. Only applicable for logs that are being compacted."},
      'max.message.bytes'           => { info: "The largest record batch size allowed by Kafka (after compression if compression is enabled). If this is increased and there are consumers older than 0.10.2, the consumers' fetch size must also be increased so that they can fetch record batches this large. In the latest message format version, records are always grouped into batches for efficiency. In previous message format versions, uncompressed records are not grouped into batches and this limit only applies to a single record in that case."},
      'message.downconversion.enable'=> { info: "This configuration controls whether down-conversion of message formats is enabled to satisfy consume requests. When set to false, broker will not perform down-conversion for consumers expecting an older message format. The broker responds with UNSUPPORTED_VERSION error for consume requests from such older clients. This configurationdoes not apply to any message format conversion that might be required for replication to followers."},
      'message.format.version'      => { info: "[DEPRECATED] Specify the message format version the broker will use to append messages to the logs. The value of this config is always assumed to be `3.0` if `inter.broker.protocol.version` is 3.0 or higher (the actual config value is ignored). Otherwise, the value should be a valid ApiVersion. Some examples are: 0.10.0, 1.1, 2.8, 3.0. By setting a particular message format version, the user is certifying that all the existing messages on disk are smaller or equal than the specified version. Setting this value incorrectly will cause consumers with older versions to break as they will receive messages with a format that they don't understand."},
      'message.timestamp.difference.max.ms'=> { info: "The maximum difference allowed between the timestamp when a broker receives a message and the timestamp specified in the message. If message.timestamp.type=CreateTime, a message will be rejected if the difference in timestamp exceeds this threshold. This configuration is ignored if message.timestamp.type=LogAppendTime."},
      'message.timestamp.type'      => { info: "Define whether the timestamp in the message is message create time or log append time. The value should be either `CreateTime` or `LogAppendTime`"},
      'min.cleanable.dirty.ratio'   => { info: "This configuration controls how frequently the log compactor will attempt to clean the log (assuming log compaction is enabled). By default we will avoid cleaning a log where more than 50% of the log has been compacted. This ratio bounds the maximum space wasted in the log by duplicates (at 50% at most 50% of the log could be duplicates). A higher ratio will mean fewer, more efficient cleanings but will mean more wasted space in the log. If the max.compaction.lag.ms or the min.compaction.lag.ms configurations are also specified, then the log compactor considers the log to be eligible for compaction as soon as either: (i) the dirty ratio threshold has been met and the log has had dirty (uncompacted) records for at least the min.compaction.lag.ms duration, or (ii) if the log has had dirty (uncompacted) records for at most the max.compaction.lag.ms period."},
      'min.compaction.lag.ms'       => { info: "The minimum time a message will remain uncompacted in the log. Only applicable for logs that are being compacted."},
      'min.insync.replicas'         => { info: "When a producer sets acks to 'all' (or '-1'), this configuration specifies the minimum number of replicas that must acknowledge a write for the write to be considered successful. If this minimum cannot be met, then the producer will raise an exception (either NotEnoughReplicas or NotEnoughReplicasAfterAppend). When used together, min.insync.replicas and acks allow you to enforce greater durability guarantees. A typical scenario would be to create a topic with a replication factor of 3, set min.insync.replicas to 2, and produce with acks of 'all'. This will ensure that the producer raises an exception if a majority of replicas do not receive a write."},
      'preallocate'                 => { info: "True if we should preallocate the file on disk when creating a new log segment."},
      'retention.bytes'             => { info: "This configuration controls the maximum size a partition (which consists of log segments) can grow to before we will discard old log segments to free up space if we are using the 'delete' retention policy. By default there is no size limit only a time limit. Since this limit is enforced at the partition level, multiply it by the number of partitions to compute the topic retention in bytes."},
      'retention.ms'                => { info: "This configuration controls the maximum time we will retain a log before we will discard old log segments to free up space if we are using the 'delete' retention policy. This represents an SLA on how soon consumers must read their data. If set to -1, no time limit is applied."},
      'segment.bytes'               => { info: "This configuration controls the segment file size for the log. Retention and cleaning is always done a file at a time so a larger segment size means fewer files but less granular control over retention."},
      'segment.index.bytes'         => { info: "This configuration controls the size of the index that maps offsets to file positions. We preallocate this index file and shrink it only after log rolls. You generally should not need to change this setting."},
      'segment.jitter.ms'           => { info: "The maximum random jitter subtracted from the scheduled segment roll time to avoid thundering herds of segment rolling"},
      'segment.ms'                  => { info: "This configuration controls the period of time after which Kafka will force the log to roll even if the segment file isn't full to ensure that retention can delete or compact old data."},
      'unclean.leader.election.enable'=> { info: "Indicates whether to enable replicas not in the ISR set to be elected as leader as a last resort, even though doing so may result in data loss."},
    }.clone
  end
end