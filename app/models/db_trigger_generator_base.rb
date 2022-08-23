class DbTriggerGeneratorBase < Database
  attr_reader :successes, :errors, :load_sqls
  TRIGGER_NAME_PREFIX = "M_CDC_"                                                # owner of trigger is always db_user, must not be part of trigger name

  ### class methods following

  # generate trigger name from short operation (I/U/D) and schema/table
  def self.build_trigger_name(table, operation)
    # Ensure trigger name remains unique even if schema or table IDs change (e.g. after export + reimport)
    "#{TRIGGER_NAME_PREFIX}#{operation}_#{table.schema.id}_#{table.id}_#{table.schema.name.sum}_#{table.name.sum}"
  end

  def self.short_operation_from_long(operation)
    case operation
    when 'INSERT' then 'I'
    when 'UPDATE' then 'U'
    when 'DELETE' then 'D'
    end
  end

  def self.long_operation_from_short(operation)
    case operation
    when 'I' then 'INSERT'
    when 'U' then 'UPDATE'
    when 'D' then 'DELETE'
    end
  end

  ### instance methods following

  # @param schema_id [Integer] ID in table schemas
  # @param dry_run [TrueClass | FalseClass] suppress DML execution?
  def initialize(schema_id:, dry_run:)
    @schema             = Schema.find schema_id
    raise "Parameter dry_run should be of boolean type, not '#{dry_run.class}'" if dry_run.class != TrueClass && dry_run.class != FalseClass
    @dry_run            = dry_run
    @successes          = []                                                    # created triggers
    @errors             = []                                                    # errors during trigger creation
    @load_sqls          = []                                                    # PL/SQL snipped for initial load
    @existing_triggers  = build_existing_triggers_list
    # Build structure for expected triggers:
    # table_name: { operation: { columns: [ {column_name:, ...} ], condition: }}
    @expected_triggers  = build_expected_triggers_list
  end

  # call subroutines defined in DB-specific classes
  def generate_table_triggers(table_id:)
    table = Table.find table_id
    ['I', 'U', 'D'].each do |operation|
      drop_obsolete_triggers(table, operation)
      if trigger_expected?(table, operation)
        check_for_physical_column_existence(table, operation)
        create_or_rebuild_trigger(table, operation)
        create_load_sql(table) if operation == 'I' && table.yn_initialization == 'Y' # init table if requested regardless of whether trigger code has changed or not
      end
    end
  rescue Exception => e                                                         # Ensure other tables are processed if error occurs at one table
    ExceptionHelper.log_exception(e, 'DbTriggerGeneratorOracle.generate_table_triggers', additional_msg: "schema='#{table.schema.name}', table='#{table.name}'")
    @errors << {
      table_id:           table.id,
      table_name:         table.name,
      trigger_name:       '[not specified]',
      exception_class:    e.class.name,
      exception_message:  e.message,
      sql:                '[not specified]'
    }
  end

  # Should trigger exist here? based on configuration
  def trigger_expected?(table, operation)
    @expected_triggers[table.name] &&                                           # Table should have triggers
      @expected_triggers[table.name][operation]                                 # Operation has columns to trigger
  end

  # check if orphaned MOVEX-CDC triggers exist in DB for not existing table IDs in TABLES
  # This may result in records in table Event_Logs which cannot be processed to Kafka
  def check_for_orphaned_triggers(schema)
    found_msg = nil
    found_number = 0
    table_ids = Table.where(schema_id: schema.id).map{|t| t.id}
    @existing_triggers.each do |trigger|
      trigger_name_rest = trigger['trigger_name'].sub(TRIGGER_NAME_PREFIX, '') # Rest is I_<schema_id>_<table_id>
      trigger_name_rest = trigger_name_rest[2,100]                              # remove leading operation and _
      delimiter_pos = trigger_name_rest.index('_')                               # delimiting _ between schema_id and table_id
      unless delimiter_pos.nil?
        trigger_schema_id = trigger_name_rest[0, delimiter_pos].to_i
        trigger_name_rest = trigger_name_rest[delimiter_pos+1, 100]             # table_id + rest
        delimiter_pos = trigger_name_rest.index('_')                            # delimiting _ between schema_id and table_id
        unless delimiter_pos.nil?
          trigger_table_id = trigger_name_rest[0, delimiter_pos].to_i
        else
          trigger_table_id = 0
        end
      else
        trigger_schema_id = 0
        trigger_table_id = 0
      end
      if trigger_schema_id != schema.id || table_ids.find{|t| t == trigger_table_id}.nil?
        Rails.logger.error('DbTriggerGeneratorBase.check_for_orphaned_triggers') do
          "Orphaned MOVEX-CDC trigger '#{trigger['trigger_name']}' found for table '#{schema.name}.#{trigger['table_name']}'!
This table does not have a corresponding record in configured tables of MOVEX-CDC!
Events created by this trigger may block the whole processing of events to Kafka!
Please fix (remove) this trigger manually before proceeding!"
        end

        found_msg = "Trigger '#{trigger['trigger_name']}' of table #{schema.name}.#{trigger['table_name']}"
        found_number += 1
      end
    end
    unless found_msg.nil?
      raise "#{found_number} orphaned trigger(s) found for schema #{schema.name}!
Tables of this orphaned triggers do not have a corresponding record in configured tables of MOVEX-CDC!
Events created by this triggers may block the whole processing of events to Kafka!
Please fix (remove) this trigger(s) manually before proceeding!
Example: #{found_msg}.
The whole list of orphaned triggers can be found in server log.
"
    end
  end
end
