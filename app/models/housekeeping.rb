class Housekeeping

  @@instance = nil
  def self.get_instance
    @@instance = Housekeeping.new if @@instance.nil?
    @@instance
  end

  def do_housekeeping
    if @last_housekeeping_started.nil?
      do_housekeeping_internal
      true
    else
      Rails.logger.error "Housekeeping.do_housekeeping: Last run started at #{@last_housekeeping_started} not yet finished!"
      false
    end
  end


  private
  def initialize                                                                # get singleton by get_instance only
    @last_housekeeping_started = nil                                            # semaphore to prevent multiple execution
  end

  def do_housekeeping_internal
    @last_housekeeping_started = Time.now

    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      TableLess.select_all("SELECT Partition_Name, High_Value
                            FROM   User_Tab_Partitions
                            WHERE  Table_Name = 'EVENT_LOGS'
                            AND Partition_Name != 'MIN'"
      ).each do |part|

      end
    end

  ensure
    @last_housekeeping_started = nil
  end


end