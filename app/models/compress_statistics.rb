class CompressStatistics

  @@instance = nil
  def self.get_instance
    @@instance = CompressStatistics.new if @@instance.nil?
    @@instance
  end

  def do_compress
    if @last_compress_started.nil?
      Rails.logger.debug "CompressStatistics.do_compress: Start compressing"
      do_compress_internal
      true                                                                      # signal state for test run only
    else
      Rails.logger.error "CompressStatistics.do_compress: Last run started at #{@last_compress_started} not yet finished!"
      false                                                                     # signal state for test run only
    end
  end


  private
  def initialize                                                                # get singleton by get_instance only
    @last_compress_started = nil                                                # semaphore to prevent multiple execution
  end

  def do_compress_internal
    @last_compress_started = Time.now
    process_age_group(3.months)                                                 # Compress records older than 3 months to day
    process_age_group(14.days)                                                  # Compress records older than 14 days to hour
  ensure
    @last_compress_started = nil
  end

  def process_age_group(min_age)
    begin                                                                       # process a limited number of groups at once
      record_groups = get_record_groups(min_age)
      record_groups.each do |rg|
        compress_single_group(rg)
      end
    end while record_groups.count > 0
  end

  def get_record_groups(min_age)
    Database.select_all "SELECT *
                         FROM (
                               SELECT table_id, operation, Min(End_Timestamp) min_end_timestamp, MAX(End_Timestamp) max_end_timestamp,
                                      SUM(events_success)         events_success,
                                      SUM(events_delayed_errors)  events_delayed_errors,
                                      SUM(events_final_errors)    events_final_errors,
                                      SUM(events_d_and_c_retries) events_d_and_c_retries,
                                      SUM(events_delayed_retries) events_delayed_retries
                               FROM   Statistics
                               WHERE  End_Timestamp < :min_age
                               GROUP BY Table_ID, Operation, #{time_group_expression(min_age)}
                               HAVING COUNT(*) > 1
                              )
                         #{Database.result_limit_expression('row_limit', sole_filter: true)}
                        ", {min_age: Time.now - min_age, row_limit: 20000}
  end

  def compress_single_group(record_group)
    ActiveRecord::Base.transaction do
      # delete multiple records
      Database.execute "DELETE FROM Statistics WHERE Table_ID = :table_id AND Operation = :operation
                        AND End_Timestamp >= :min_ts AND End_Timestamp <= :max_ts",
                       { table_id:  record_group['table_id'],
                         operation: record_group['operation'],
                         min_ts:    record_group['min_end_timestamp'],
                         max_ts:    record_group['max_end_timestamp']
                       }
      # replace with compressed record
      Statistic.new(
        table_id:               record_group['table_id'],
        operation:              record_group['operation'],
        end_timestamp:          record_group['max_end_timestamp'],
        events_success:         record_group['events_success'],
        events_delayed_errors:  record_group['events_delayed_errors'],
        events_final_errors:    record_group['events_final_errors'],
        events_d_and_c_retries: record_group['events_d_and_c_retries'],
        events_delayed_retries: record_group['events_delayed_retries'],
      ).save!
    end
  end

  # get database specific expression for time grouping
  def time_group_expression(min_age)
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      case min_age
      when 3.months                                                             # group by day
        "TRUNC(End_Timestamp, 'DD')"
      when 14.days                                                              # group by hour
        "TRUNC(End_Timestamp, 'HH24')"
      end
    when 'SQLITE' then
      case min_age
      when 3.months
        "date(End_Timestamp)"
      when 14.days
        "strftime('%Y-%m-%d %H', End_Timestamp)"
      end
    else
      raise "CompressStatistics.time_group_expression: Missing value for '#{Trixx::Application.config.trixx_db_type}'"
    end
  end
end