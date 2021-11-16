class CreateEventLogFinalErrors < ActiveRecord::Migration[6.0]
  def up
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      # Start first partition with current date to ensure less than 1 Mio. partitions within the next years
      # NUMBER(18) is the maximum numeric value storable in 64bit long value
      # high_value of first partition is set back in history for tests
      EventLog.connection.execute("\
      CREATE TABLE Event_Log_Final_Errors (
        ID          NUMBER(18)    NOT NULL,
        Table_ID    NUMBER(18)    NOT NULL,
        Operation   CHAR(1)       NOT NULL,
        DBUser      VARCHAR2(128) NOT NULL,
        Payload     CLOB          NOT NULL,
        Msg_Key     VARCHAR2(4000),
        Created_At  TIMESTAMP(6)  NOT NULL,
        Error_Time  TIMESTAMP(6)  NOT NULL,
        Error_Msg   CLOB          NOT NULL
        )
        PCTFREE 0
        INITRANS 16
        #{"PARTITION BY RANGE (Error_Time) INTERVAL( NUMTODSINTERVAL(1,'HOUR'))
           ( PARTITION MIN VALUES LESS THAN (TO_DATE('#{200.days.ago.strftime "%Y-%m-%d"} 00:00:00', 'YYYY-MM-DD HH24:MI:SS', 'NLS_CALENDAR=GREGORIAN')) )" if Trixx::Application.partitioning?}
                                  ")
    else
      create_table :event_log_final_errors do |t|
        t.references  :table,                   null: false,  comment: 'Reference to tables'
        t.string      :operation, limit: 1,     null: false,  comment: 'Operation type /I/U/D'
        t.string      :dbuser,    limit: 128,   null: false,  comment: 'Name of connected DB user'
        t.text        :payload,                 null: false,  comment: 'Payload of message with old and new values'
        t.string      :msg_key,   limit: 4000,  null: true,   comment: 'Optional Kafka message key to ensure all messages of same key are stored in same partition'
        t.timestamp   :created_at,              null: false,  comment: 'Record creation timestamp'
        t.timestamp   :error_time,              null: false,  comment: 'Timestamp of final error after retries'
        t.text        :error_msg,               null: false,  comment: 'Final error message after retries'
      end
    end
  end

  def down
    drop_table(:event_log_final_errors)
  end
end
