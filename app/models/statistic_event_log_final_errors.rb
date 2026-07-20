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
    # Retrieve aggregation of data records written to table Event_Log_Final_Errors during the last 120 minutes (7200 seconds)
    @record_cache = Database.select_all("\
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
        WHERE
            elfe.error_time >= :start_eval_period
        GROUP BY
            sch.NAME
            ,tab.NAME
            ,elfe.OPERATION
        ORDER BY
            sch.NAME
            ,tab.NAME
            ,elfe.OPERATION
      ",{start_eval_period: Time.now - (120 * 60)}
    )
  end

  def get_statistic()
    @record_cache
  end

  private
  def initialize
    @record_cache = {}
    refresh_statistic
  end
end