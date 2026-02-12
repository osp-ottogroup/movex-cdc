class Housekeeping

  @@instance = nil
  def self.get_instance
    @@instance = Housekeeping.new if @@instance.nil?
    @@instance
  end

  # public class helper methods
  # extract the time from high value string of Oracle partition
  # @param [String] high_value The high value as beeing read from LONG column
  # @return [Time] The time expression of high value
  def self.get_time_from_oracle_high_value(high_value)
    raise "Housekeeping.get_time_from_oracle_high_value: Parameter high_value should not be nil" if high_value.nil?
    hv_string = high_value.split("'")[1].strip                            # extract "2021-04-14 00:00:00" from "TIMESTAMP' 2021-04-14 00:00:00'"
    Time.new(hv_string[0,4].to_i, hv_string[5,2].to_i, hv_string[8,2].to_i, hv_string[11,2].to_i, hv_string[14,2].to_i, hv_string[17,2].to_i)
  end


  def do_housekeeping
    if @last_housekeeping_started.nil?
      Rails.logger.debug('Housekeeping.do_housekeeping') { "Start housekeeping" }
      do_housekeeping_internal
    else
      Rails.logger.error('Housekeeping.do_housekeeping') { "Last run started at #{@last_housekeeping_started} not yet finished!" }
    end
  end

  # Calculate the maximum age of the high value of the first partition
  # @return [Integer] the maximum age in seconds to not overflow the max. partition count
  def max_min_partition_age
    max_possible_partition_count = 1024*1024-1
    max_distance_seconds = max_possible_partition_count * MovexCdc::Application.config.partition_interval / 4 # 1/4 of allowed number of possible partitions
    max_distance_seconds = 1440*365*60 if max_distance_seconds > 1440*365*60 # largest distance for oldest partition is one year
    max_distance_seconds
  end


  private
  def initialize                                                                # get singleton by get_instance only
    @last_housekeeping_started = nil                                            # semaphore to prevent multiple execution
  end

  # Drop outdated partitions
  def do_housekeeping_internal
    @last_housekeeping_started = Time.now
    log_partitions                                                              # log all existing partitions

    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      # check all partitions for deletion except the youngest one, no matter if they are interval or not
      if MovexCdc::Application.partitioning?
        partitions_to_check = Database.select_all "\
          WITH Partitions AS (SELECT Partition_Name, Partition_Position, Interval, High_Value
                              FROM   User_Tab_Partitions
                              WHERE  Table_Name = 'EVENT_LOGS'
                             )
          SELECT p.Partition_Name, p.Partition_Position, p.High_Value, stats.Interval_Count, stats.Max_Partition_Position
          FROM   Partitions p
          CROSS JOIN (SELECT SUM(DECODE(Interval, 'YES', 1, 0)) Interval_Count, MAX(Partition_Position) Max_Partition_Position
                      FROM Partitions
                     ) stats
          /* do not check the youngest or last partition */
          WHERE  Partition_Position != (SELECT MAX(Partition_Position) FROM Partitions)
          ORDER BY Partition_Position
        "

        # check for locks on partitions only once to ensure that expensive SQL is executed as little as possible
        locked_partitions = {}
        Database.select_all("\
          SELECT DISTINCT o.SubObject_Name Partition_Name, l.Inst_ID, l.SID, l.ctime
          FROM   gv$Lock l
          JOIN   User_Objects o ON o.Object_ID = l.ID1
          WHERE  o.Object_Name    = 'EVENT_LOGS'
          AND    o.SubObject_Name IS NOT NULL /* There is always a lock record for the whole table also if a partition is locked */
        ").each do |row|
          locked_partitions[row.partition_name] = [] unless locked_partitions.has_key? row.partition_name
          locked_partitions[row.partition_name] << { inst_id: row.inst_id, sid: row.sid, lock_secs: row.ctime }
        end

        partitions_to_check.each do |part|
          # if only range partitions exists (no interval) than preserve the youngest two range partitions
          if part.interval_count > 0 || ( part.partition_position < part.max_partition_position - 2 )
            if locked_partitions.has_key? part.partition_name                   # Don't check partition that has pending transactions
              high_value_time = Housekeeping.get_time_from_oracle_high_value(part.high_value)
              if high_value_time < Time.now - max_min_partition_age.seconds
                msg = "Partition #{part.partition_name} with high value '#{part.high_value}' still has pending transactions but needs to be dropped to avoid ORA-14300! #{locked_partitions[part.partition_name] }"
                Rails.logger.error('Housekeeping.do_housekeeping_internal') { msg }
                raise "Housekeeping.do_housekeeping_internal: #{msg}"
              else
                min_lock_age_days = 2
                if high_value_time < Time.now - min_lock_age_days.days
                  Rails.logger.warn('Housekeeping.do_housekeeping_internal'){ "There are pending transactions on partition #{part.partition_name} with high value #{part.high_value} older than #{min_lock_age_days} days! #{locked_partitions[part.partition_name]}" }
                end
                Rails.logger.info('Housekeeping.do_housekeeping_internal'){ "Check partition #{part.partition_name} with high value #{part.high_value} for drop not possible because there are pending transactions! #{locked_partitions[part.partition_name] }" }
              end
            else
              EventLog.check_and_drop_partition(part.partition_name, 'Housekeeping.do_housekeeping_internal', lock_already_checked: true)
            end
          end
        end
      end
    end

  ensure
    @last_housekeeping_started = nil
  end

  private
  def log_partitions
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        Rails.logger.debug('Housekeeping.log_partitions') { "All currently existing partitions" }
        Database.select_all("SELECT * FROM User_Tab_Partitions WHERE  Table_Name = 'EVENT_LOGS' ORDER BY Partition_Position").each do |p|
          Rails.logger.debug('Housekeeping.log_partitions') { "Pos=#{p.partition_position} #{p.partition_name} Interval=#{p.interval} HighValue=#{p.high_value}" }
        end
      end
    end
  end

  # Ensure that an empty interval partition will be created
  # @param [Time] created_at the time of the record to be inserted
  # @return [void]
  def force_interval_partition_creation(created_at)
    ActiveRecord::Base.transaction do
      Database.execute "INSERT INTO Event_Logs(ID, Created_At, Table_Id, Operation, DBUser, Payload) VALUES (Event_Logs_Seq.NextVal, TO_DATE(:created_at, 'YYYY-MM-DD HH24:MI:SS'), 5, 'I', 'hugo', 'hugo')",
                       binds: { created_at: created_at.strftime('%Y-%m-%d %H:%M:%S') } # Don't use Time directly as bind variable because of timezone drift
      raise ActiveRecord::Rollback
    end
  end

  # Calculate the default high value of the first partition
  # @param [Time] second_hv_time the high value time of the second partition
  # @return [Time] the suggested hich value time of the first partition to have a valid distance to the current time
  def default_first_partiton_high_value(second_hv_time)
    hv_time = Time.now - 100*86400 # 100 days back
    if second_hv_time < hv_time                                                 # the second partition is not younger then the new expected time for the first partition
      hv_time = second_hv_time                                                  # use high value of the second partition if the second partition is older than 100 days
    end
    hv_time
  end
end