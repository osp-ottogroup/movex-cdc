class ExtendEventLogsIndex < ActiveRecord::Migration[6.0]
  def up
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      unless MovexCdc::Application.partitioning?
        # Ensure that long lasting full table scan on table with unpredictable size is not used
        # in contrast to partitioned table where full table scan should be used
        EventLog.connection.execute("\
        CREATE UNIQUE INDEX Event_Logs_PK ON Event_logs(ID)
          PCTFREE 10
          INITRANS #{MovexCdc::Application.config.max_simultaneous_transactions}
        ")
      end
    end
  end

  def down
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      unless MovexCdc::Application.partitioning?
        EventLog.connection.execute("DROP INDEX Event_Logs_PK")
      end
    end
  end
end
