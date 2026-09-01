class StatisticEventLogFinalErrors
  @instance = nil

  def self.get_instance
    @instance = StatisticEventLogFinalErrors.new if @instance.nil?
    @instance
  end

  # Necessary only for test to ensure dealing with fresh instance
  def self.remove_instance
    @instance = nil
  end

  def refresh_statistic()
    # Retrieve aggregation of data records written to table Event_Log_Final_Errors without any time limit,
    # because old records are deleted by housekeeping processes after several days.
    record_cache = Database.select_all("\
      SELECT
        sch.NAME AS schema_name
        ,tab.NAME AS table_name
        ,elfe.OPERATION AS operation
        ,COUNT(*) AS current_value
      FROM
        Event_Log_Final_Errors elfe
        INNER JOIN Tables tab
          ON tab.id = elfe.table_id
        INNER JOIN Schemas sch
          ON sch.id = tab.schema_id
      GROUP BY
        sch.NAME
        ,tab.NAME
        ,elfe.OPERATION
      ORDER BY
        sch.NAME
        ,tab.NAME
        ,elfe.OPERATION"
    )
    @mutex.synchronize do
      @record_cache = record_cache
    end
  end

  def get_statistic()
    @mutex.synchronize do
      # Sort results by schema_name, table_name, and operation to ensure consistent ordering
      @record_cache.sort_by do |record|
        [record['schema_name'], record['table_name'], record['operation']]
      end
    end
  end

  private
  def initialize
    @record_cache = {}
    @mutex = Mutex.new
    refresh_statistic
  end
end