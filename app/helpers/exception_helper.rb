require 'java'

module ExceptionHelper
  def self.exception_backtrace(exception, line_number_limit=nil)
    result = "Stack-Trace for exception '#{exception.class} #{exception.message}' is:\n"
    curr_line_no=0
    exception.backtrace.each do |bt|
      result << "#{bt}\n" if line_number_limit.nil? || curr_line_no < line_number_limit # report First x lines of stacktrace in log
      curr_line_no += 1
    end
    result
  end

  # log exception as ERROR
  # @param exception      The exception object
  # @param context        The class and method name where the exception occured
  # @param additional_msg Additional text to log in subseauent lines
  def self.log_exception(exception, context, additional_msg: nil)
    following_lines = ''
    following_lines << explain_exception(exception) unless explain_exception(exception).nil?
    following_lines << "\n" unless following_lines == ''
    following_lines << "#{additional_msg}\n" unless additional_msg.nil?
    if Rails.logger.level == 0 # DEBUG
      mem_info = memory_info_string
      following_lines << "#{mem_info}\n" if mem_info && mem_info != ''
      following_lines << exception_backtrace(exception)
    else
      following_lines << "Switch log level to 'debug' to get additional stack trace and memory info for exceptions!"
    end
    following_lines << "\n" unless following_lines == ''

    Rails.logger.error(context){ "Exception: #{exception.class}: #{exception.message}#{"\n" unless following_lines == ''}#{following_lines}" }
    #explanation = explain_exception(exception)
    #Rails.logger.error explanation if explanation
    #Rails.logger.error "Context: #{context}"
    #if Rails.logger.level == 0 # DEBUG
    #  mem_info = memory_info_string
    #  Rails.logger.error "#{mem_info}\n" if mem_info && mem_info != ''
    #  log_exception_backtrace(exception)
    #else
    #  Rails.logger.error "Switch log level to 'debug' to get additional stack trace and memory info for exceptions!"
    #end
  end

  def self.warn_with_backtrace(context, message)
    Rails.logger.warn(context){ message }
    if Rails.logger.level == 0 # DEBUG
      backtrace_msg = "Stacktrace for previous warning follows:\n"
      Thread.current.backtrace.each do |bt|
        backtrace_msg << "#{bt}\n"
      end
      Rails.logger.debug(context){ backtrace_msg }
    end
  end

  def self.memory_info_string
    output = ''
    memory_info_hash.each do |key, value|
      output << "#{value[:name]} = #{value[:value]}, " unless value.nil?
    end
    output
  end

  # get Hash with details
  def self.memory_info_hash
    memoryUsage = java.lang.management.ManagementFactory.getMemoryMXBean.getHeapMemoryUsage
    gb = (1024 * 1024 * 1024).to_f
    {
      total_memory:         { name: 'Total OS Memory (GB)',      value: gb_value_from_proc('MemTotal',      'hw.memsize') },
      available_memory:     { name: 'Available OS Memory (GB)',  value: gb_value_from_proc('MemAvailable',  'hw.memsize') },   # Real avail. mem. for application. Max-OS: phys. mem. used to ensure valid test becaus real mem avail is not available
      free_memory:          { name: 'Free Memory OS (GB)',       value: gb_value_from_proc('MemFree',       'page_free_count') },   # free mem. may be much smaller than real avail. mem. for app.
      total_swap:           { name: 'Total OS Swap (GB)',        value: gb_value_from_proc('SwapTotal',     'vm.swapusage') },
      free_swap:            { name: 'Free OS Swap (GB)',         value: gb_value_from_proc('SwapFree',      'vm.swapusage') },
      initial_java_heap:    { name: 'Initial Java Heap (GB)',    value: (memoryUsage.getInit/gb).round(3) },
      used_java_heap:       { name: 'Used Java Heap (GB)',       value: (memoryUsage.getUsed/gb).round(3) },
      committed_java_heap:  { name: 'Committed Java Heap (GB)',  value: (memoryUsage.getCommitted/gb).round(3) },
      maximum_java_heap:    { name: 'Maximum Java Heap (GB)',    value: (memoryUsage.getMax/gb).round(3) },
    }
  end

  # wait x seconds for a Mutex than raise or leave
  def self.limited_wait_for_mutex(mutex:, raise_exception: false, max_wait_time_secs: 3)
    1.upto(max_wait_time_secs) do
      return unless mutex.locked?                                               # Leave the function without any action
      Rails.logger.warn("ExceptionHelper.limited_wait_for_mutex: Mutex is locked, waiting one second, called from #{Thread.current.backtrace.fifth}")
      sleep 1
    end
    if raise_exception
      raise "ExceptionHelper.limited_wait_for_mutex: Mutex is still locked after #{max_wait_time_secs} seconds"
    else
      ExceptionHelper.warn_with_backtrace 'ExceptionHelper.limited_wait_for_mutex', "Mutex is still locked after #{max_wait_time_secs} seconds! Continuing."
    end
  end

  private
  def self.gb_value_from_proc(key_linux, key_darwin)
    retval = nil
    case RbConfig::CONFIG['host_os']
    when 'linux' then
      cmd = "cat /proc/meminfo 2>/dev/null | grep #{key_linux}"
      output = %x[ #{cmd} ]
      retval = (output.split(' ')[1].to_f/(1024*1024)).round(3) if output[key_linux]
    when 'darwin' then
      cmd = "sysctl -a | grep '#{key_darwin}'"
      output = %x[ #{cmd} ]
      if output[key_darwin]                                                     # anything found?
        if key_darwin == 'vm.swapusage'
          case key_linux
          when 'SwapTotal' then
            retval = (output.split(' ')[3].to_f / 1024).round(3)
          when 'SwapFree' then
            retval = (output.split(' ')[9].to_f / 1024).round(3)
          end
        else
          page_multitplier = 1                                                       # bytes
          page_multitplier= 4096 if output['vm.page']                                # pages
          retval = (output.split(' ')[1].to_f * page_multitplier / (1024*1024*1024)).round(3)
        end
      end
    end
    retval
  end

  # try to interpret what happened at Kafka
  def self.explain_exception(exception)
    case exception.class.name
    # explain error codes like named at https://kafka.apache.org/protocol#protocol_error_codes
    when 'Kafka::UnknownError' then
      case exception.message.strip
      when 'Unknown error with code -1' then 'UNKNOWN_SERVER_ERROR: False	The server experienced an unexpected error when processing the request.'
      when 'Unknown error with code 0' then 'NONE:'
      when 'Unknown error with code 1' then 'OFFSET_OUT_OF_RANGE:	The requested offset is not within the range of offsets maintained by the server.'
      when 'Unknown error with code 2' then 'CORRUPT_MESSAGE:	This message has failed its CRC checksum, exceeds the valid size, has a null key for a compacted topic, or is otherwise corrupt.'
      when 'Unknown error with code 3' then 'UNKNOWN_TOPIC_OR_PARTITION: This server does not host this topic-partition.'
      when 'Unknown error with code 4' then 'INVALID_FETCH_SIZE: The requested fetch size is invalid.'
      when 'Unknown error with code 5' then 'LEADER_NOT_AVAILABLE: There is no leader for this topic-partition as we are in the middle of a leadership election.'
      when 'Unknown error with code 6' then 'NOT_LEADER_OR_FOLLOWER: For requests intended only for the leader, this error indicates that the broker is not the current leader. For requests intended for any replica, this error indicates that the broker is not a replica of the topic partition.'
      when 'Unknown error with code 7' then 'REQUEST_TIMED_OUT: The request timed out.'
      when 'Unknown error with code 8' then 'BROKER_NOT_AVAILABLE: The broker is not available.'
      when 'Unknown error with code 9' then 'REPLICA_NOT_AVAILABLE: The replica is not available for the requested topic-partition. Produce/Fetch requests and other requests intended only for the leader or follower return NOT_LEADER_OR_FOLLOWER if the broker is not a replica of the topic-partition.'
      when 'Unknown error with code 10' then 'MESSAGE_TOO_LARGE: The request included a message larger than the max message size the server will accept.'
      when 'Unknown error with code 11' then 'STALE_CONTROLLER_EPOCH: The controller moved to another broker.'
      when 'Unknown error with code 12' then 'OFFSET_METADATA_TOO_LARGE: False	The metadata field of the offset request was too large.'
      when 'Unknown error with code 13' then 'NETWORK_EXCEPTION: The server disconnected before a response was received.'
      when 'Unknown error with code 14' then 'COORDINATOR_LOAD_IN_PROGRESS: The coordinator is loading and hence cannot process requests.'
      when 'Unknown error with code 15' then 'COORDINATOR_NOT_AVAILABLE: The coordinator is not available.'
      when 'Unknown error with code 16' then 'NOT_COORDINATOR: This is not the correct coordinator.'
      when 'Unknown error with code 17' then 'INVALID_TOPIC_EXCEPTION: The request attempted to perform an operation on an invalid topic.'
      when 'Unknown error with code 18' then 'RECORD_LIST_TOO_LARGE: The request included message batch larger than the configured segment size on the server.'
      when 'Unknown error with code 19' then 'NOT_ENOUGH_REPLICAS: Messages are rejected since there are fewer in-sync replicas than required.'
      when 'Unknown error with code 20' then 'NOT_ENOUGH_REPLICAS_AFTER_APPEND: Messages are written to the log, but to fewer in-sync replicas than required.'
      when 'Unknown error with code 21' then 'INVALID_REQUIRED_ACKS: Produce request specified an invalid value for required acks.'
      when 'Unknown error with code 22' then 'ILLEGAL_GENERATION: Specified group generation id is not valid.'
      when 'Unknown error with code 23' then "INCONSISTENT_GROUP_PROTOCOL: The group member's supported protocols are incompatible with those of existing members or first group member tried to join with empty protocol type or empty protocol list."
      when 'Unknown error with code 24' then 'INVALID_GROUP_ID: The configured groupId is invalid.'
      when 'Unknown error with code 25' then 'UNKNOWN_MEMBER_ID: The coordinator is not aware of this member.'
      when 'Unknown error with code 26' then 'INVALID_SESSION_TIMEOUT: The session timeout is not within the range allowed by the broker (as configured by group.min.session.timeout.ms and group.max.session.timeout.ms).'
      when 'Unknown error with code 27' then 'REBALANCE_IN_PROGRESS: The group is rebalancing, so a rejoin is needed.'
      when 'Unknown error with code 28' then 'INVALID_COMMIT_OFFSET_SIZE: The committing offset data size is not valid.'
      when 'Unknown error with code 29' then 'TOPIC_AUTHORIZATION_FAILED: Topic authorization failed.'
      when 'Unknown error with code 30' then 'GROUP_AUTHORIZATION_FAILED: Group authorization failed.'
      when 'Unknown error with code 31' then 'CLUSTER_AUTHORIZATION_FAILED: Cluster authorization failed.'
      when 'Unknown error with code 32' then 'INVALID_TIMESTAMP: The timestamp of the message is out of acceptable range.'
      when 'Unknown error with code 33' then 'UNSUPPORTED_SASL_MECHANISM: The broker does not support the requested SASL mechanism.'
      when 'Unknown error with code 34' then 'ILLEGAL_SASL_STATE: Request is not valid given the current SASL state.'
      when 'Unknown error with code 35' then 'UNSUPPORTED_VERSION: The version of API is not supported.'
      when 'Unknown error with code 36' then 'TOPIC_ALREADY_EXISTS: Topic with this name already exists.'
      when 'Unknown error with code 37' then 'INVALID_PARTITIONS: Number of partitions is below 1.'
      when 'Unknown error with code 38' then 'INVALID_REPLICATION_FACTOR: Replication factor is below 1 or larger than the number of available brokers.'
      when 'Unknown error with code 39' then 'INVALID_REPLICA_ASSIGNMENT: Replica assignment is invalid.'
      when 'Unknown error with code 40' then 'INVALID_CONFIG: Configuration is invalid.'
      when 'Unknown error with code 41' then 'NOT_CONTROLLER: This is not the correct controller for this cluster.'
      when 'Unknown error with code 42' then 'INVALID_REQUEST: This most likely occurs because of a request being malformed by the client library or the message was sent to an incompatible broker. See the broker logs for more details.'
      when 'Unknown error with code 43' then 'UNSUPPORTED_FOR_MESSAGE_FORMAT: The message format version on the broker does not support the request.'
      when 'Unknown error with code 44' then 'POLICY_VIOLATION: Request parameters do not satisfy the configured policy.'
      when 'Unknown error with code 45' then 'OUT_OF_ORDER_SEQUENCE_NUMBER: The broker received an out of order sequence number.'
      when 'Unknown error with code 46' then 'DUPLICATE_SEQUENCE_NUMBER: The broker received a duplicate sequence number.'
      when 'Unknown error with code 47' then 'INVALID_PRODUCER_EPOCH: Producer attempted to produce with an old epoch.'
      when 'Unknown error with code 48' then 'INVALID_TXN_STATE: The producer attempted a transactional operation in an invalid state.'
      when 'Unknown error with code 49' then 'INVALID_PRODUCER_ID_MAPPING: The producer attempted to use a producer id which is not currently assigned to its transactional id.'
      when 'Unknown error with code 50' then 'INVALID_TRANSACTION_TIMEOUT: The transaction timeout is larger than the maximum value allowed by the broker (as configured by transaction.max.timeout.ms).'
      when 'Unknown error with code 51' then 'CONCURRENT_TRANSACTIONS: The producer attempted to update a transaction while another concurrent operation on the same transaction was ongoing.'
      when 'Unknown error with code 52' then 'TRANSACTION_COORDINATOR_FENCED: Indicates that the transaction coordinator sending a WriteTxnMarker is no longer the current coordinator for a given producer.'
      when 'Unknown error with code 53' then 'TRANSACTIONAL_ID_AUTHORIZATION_FAILED: The transactional id used by MOVEX CDC is not authorized to produce messages. Explicite authorization of transactional id is required, optional as wildcard: "kafka-acls --bootstrap-server localhost:9092 --command-config adminclient-configs.conf --add --transactional-id * --allow-principal User:* --operation write"'
      when 'Unknown error with code 54' then 'SECURITY_DISABLED: Security features are disabled.'
      when 'Unknown error with code 55' then 'OPERATION_NOT_ATTEMPTED: The broker did not attempt to execute this operation. This may happen for batched RPCs where some operations in the batch failed, causing the broker to respond without trying the rest.'
      when 'Unknown error with code 56' then 'KAFKA_STORAGE_ERROR: Disk error when trying to access log file on the disk.'
      when 'Unknown error with code 57' then 'LOG_DIR_NOT_FOUND: The user-specified log directory is not found in the broker config.'
      when 'Unknown error with code 58' then 'SASL_AUTHENTICATION_FAILED: SASL Authentication failed.'
      when 'Unknown error with code 59' then "UNKNOWN_PRODUCER_ID: This exception is raised by the broker if it could not locate the producer metadata associated with the producerId in question. This could happen if, for instance, the producer's records were deleted because their retention time had elapsed. Once the last records of the producerId are removed, the producer's metadata is removed from the broker, and future appends by the producer will return this exception."
      when 'Unknown error with code 60' then 'REASSIGNMENT_IN_PROGRESS: A partition reassignment is in progress.'
      when 'Unknown error with code 61' then 'DELEGATION_TOKEN_AUTH_DISABLED: Delegation Token feature is not enabled.'
      when 'Unknown error with code 62' then 'DELEGATION_TOKEN_NOT_FOUND: Delegation Token is not found on server.'
      when 'Unknown error with code 63' then 'DELEGATION_TOKEN_OWNER_MISMATCH: Specified Principal is not valid Owner/Renewer.'
      when 'Unknown error with code 64' then 'DELEGATION_TOKEN_REQUEST_NOT_ALLOWED: Delegation Token requests are not allowed on PLAINTEXT/1-way SSL channels and on delegation token authenticated channels.'
      when 'Unknown error with code 65' then 'DELEGATION_TOKEN_AUTHORIZATION_FAILED: Delegation Token authorization failed.'
      when 'Unknown error with code 66' then 'DELEGATION_TOKEN_EXPIRED: Delegation Token is expired.'
      when 'Unknown error with code 67' then 'INVALID_PRINCIPAL_TYPE: Supplied principalType is not supported.'
      when 'Unknown error with code 68' then 'NON_EMPTY_GROUP: The group is not empty.'
      when 'Unknown error with code 69' then 'GROUP_ID_NOT_FOUND: The group id does not exist.'
      when 'Unknown error with code 70' then 'FETCH_SESSION_ID_NOT_FOUND: The fetch session ID was not found.'
      when 'Unknown error with code 71' then 'INVALID_FETCH_SESSION_EPOCH: The fetch session epoch is invalid.'
      when 'Unknown error with code 72' then 'LISTENER_NOT_FOUND: There is no listener on the leader broker that matches the listener on which metadata request was processed.'
      when 'Unknown error with code 73' then 'TOPIC_DELETION_DISABLED: Topic deletion is disabled.'
      when 'Unknown error with code 74' then 'FENCED_LEADER_EPOCH: The leader epoch in the request is older than the epoch on the broker.'
      when 'Unknown error with code 75' then 'UNKNOWN_LEADER_EPOCH: The leader epoch in the request is newer than the epoch on the broker.'
      when 'Unknown error with code 76' then 'UNSUPPORTED_COMPRESSION_TYPE: The requesting client does not support the compression type of given partition.'
      when 'Unknown error with code 77' then 'STALE_BROKER_EPOCH: Broker epoch has changed.'
      when 'Unknown error with code 78' then 'OFFSET_NOT_AVAILABLE:OFFSET_NOT_AVAILABLE	78	True	The leader high watermark has not caught up from a recent leader election so the offsets cannot be guaranteed to be monotonically increasing.'
      when 'Unknown error with code 79' then 'MEMBER_ID_REQUIRED: The group member needs to have a valid member id before actually entering a consumer group.'
      when 'Unknown error with code 80' then 'PREFERRED_LEADER_NOT_AVAILABLE: The preferred leader was not available.'
      when 'Unknown error with code 81' then 'GROUP_MAX_SIZE_REACHED: The consumer group has reached its max size.'
      when 'Unknown error with code 82' then 'FENCED_INSTANCE_ID: The broker rejected this static consumer since another consumer with the same group.instance.id has registered with a different member.id.'
      when 'Unknown error with code 83' then 'ELIGIBLE_LEADERS_NOT_AVAILABLE: Eligible topic partition leaders are not available.'
      when 'Unknown error with code 84' then 'ELECTION_NOT_NEEDED: Leader election not needed for topic partition.'
      when 'Unknown error with code 85' then 'NO_REASSIGNMENT_IN_PROGRESS: No partition reassignment is in progress.'
      when 'Unknown error with code 86' then 'GROUP_SUBSCRIBED_TO_TOPIC: Deleting offsets of a topic is forbidden while the consumer group is actively subscribed to it.'
      when 'Unknown error with code 87' then 'INVALID_RECORD: This record has failed the validation on broker and hence will be rejected. Possible reason: Log compaction is activated for topic (log.cleanup.policy=compact) but events are created by MOVEX CDC without key.'
      when 'Unknown error with code 88' then 'UNSTABLE_OFFSET_COMMIT: There are unstable offsets that need to be cleared.'
      when 'Unknown error with code 89' then 'THROTTLING_QUOTA_EXCEEDED: The throttling quota has been exceeded.'
      when 'Unknown error with code 90' then 'PRODUCER_FENCED: There is a newer producer with the same transactionalId which fences the current one.'
      when 'Unknown error with code 91' then 'RESOURCE_NOT_FOUND: A request illegally referred to a resource that does not exist.'
      when 'Unknown error with code 92' then 'DUPLICATE_RESOURCE: A request illegally referred to the same resource twice.'
      when 'Unknown error with code 93' then 'UNACCEPTABLE_CREDENTIAL: Requested credential would not meet criteria for acceptability.'
      when 'Unknown error with code 94' then 'INCONSISTENT_VOTER_SET: Indicates that the either the sender or recipient of a voter-only request is not one of the expected voters'
      when 'Unknown error with code 95' then 'INVALID_UPDATE_VERSION: The given update version was invalid.'
      when 'Unknown error with code 96' then 'FEATURE_UPDATE_FAILED: Unable to update finalized features due to an unexpected server error.'
      when 'Unknown error with code 97' then 'PRINCIPAL_DESERIALIZATION_FAILURE: Request principal deserialization failed during forwarding. This indicates an internal error on the broker cluster security setup.'
      when 'Unknown error with code 98' then 'SNAPSHOT_NOT_FOUND: Requested snapshot was not found'
      when 'Unknown error with code 99' then 'POSITION_OUT_OF_RANGE: Requested position is not greater than or equal to zero, and less than the size of the snapshot.'
      when 'Unknown error with code 100' then 'UNKNOWN_TOPIC_ID: This server does not host this topic ID.'
      when 'Unknown error with code 101' then 'DUPLICATE_BROKER_REGISTRATION: This broker ID is already in use.'
      when 'Unknown error with code 102' then 'BROKER_ID_NOT_REGISTERED: The given broker ID was not registered.'
      when 'Unknown error with code 103' then "INCONSISTENT_TOPIC_ID: The log's topic ID did not match the topic ID in the request"
      when 'Unknown error with code 104' then 'INCONSISTENT_CLUSTER_ID: The clusterId in the request does not match that found on the server'
      when 'Unknown error with code 105' then 'TRANSACTIONAL_ID_NOT_FOUND: The transactionalId could not be found'
      when 'Unknown error with code 106' then 'FETCH_SESSION_TOPIC_ID_ERROR: The fetch session encountered inconsistent topic ID usage'
      end
    end
  end
end

