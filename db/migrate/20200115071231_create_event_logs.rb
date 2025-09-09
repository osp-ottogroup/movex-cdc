class CreateEventLogs < ActiveRecord::Migration[6.0]
  def up
    msg = "######## CreateEventLogs.up: Starting migration with DB adapter '#{MovexCdc::Application.config.db_type}'"
    puts msg
    Rails.logger.warn("CreateEventLogs.up") { msg }

    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      msg =  "######## CreateEventLogs.up: Creating table Event_Logs with partitioning=#{MovexCdc::Application.partitioning?} interval=#{MovexCdc::Application.config.partition_interval} seconds"
      puts msg
      Rails.logger.warn("CreateEventLogs.up") { msg }

      # Start first partition with current date to ensure less than 1 Mio. partitions within the next years
      # NUMBER(18) is the maximum numeric value storable in 64bit long value
      # Interval is initially set to 60 seconds but can be changed by
      EventLog.connection.execute("\
      CREATE TABLE Event_Logs (
        ID          NUMBER(18)    NOT NULL,
        Table_ID    NUMBER(18)    NOT NULL,
        Operation   CHAR(1)       NOT NULL,
        DBUser      VARCHAR2(128) NOT NULL,
        Payload     CLOB          NOT NULL,
        Msg_Key     VARCHAR2(4000),
        Created_At  TIMESTAMP(6)  NOT NULL
        )
        PCTFREE 0
        INITRANS #{MovexCdc::Application.config.max_simultaneous_transactions}
        LOB(Payload) STORE AS (CACHE)
        #{"PARTITION BY RANGE (Created_At) INTERVAL( NUMTODSINTERVAL(#{MovexCdc::Application.config.partition_interval},'SECOND'))
           ( PARTITION MIN VALUES LESS THAN (TO_DATE('#{Time.now.strftime "%Y-%m-%d"} 00:00:00', 'YYYY-MM-DD HH24:MI:SS', 'NLS_CALENDAR=GREGORIAN')) )" if MovexCdc::Application.partitioning?}
      ")

      # Sequence Event_Logs_Seq is handled in ExtendEventLogs2
    when 'SQLITE' then
      create_table :event_logs do |t|
        t.references  :table,                   null: false,  comment: 'Reference to tables'
        t.string      :operation, limit: 1,     null: false,  comment: 'Operation type i/I/U/D'
        t.string      :dbuser,    limit: 128,   null: false,  comment: 'Name of connected DB user'
        t.text        :payload,                 null: false,  comment: 'Payload of message with old and new values'
        t.string      :msg_key,   limit: 4000,  null: true,   comment: 'Optional Kafka message key to ensure all messages of same key are stored in same partition'
        t.timestamp   :created_at,              null: false,  comment: 'Record creation timestamp'
      end
    else
      raise "CreateEventLogs: DBTYPE '#{MovexCdc::Application.config.db_type}' is not supported"
    end
  end

  def down

    msg = "######## CreateEventLogs.down: Reverting migration with DB adapter '#{MovexCdc::Application.config.db_type}'"
    puts msg
    Rails.logger.warn("CreateEventLogs.down") { msg }

    drop_table(:event_logs)
  end
end
