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

  def initialize(schema_id:, user_options:, dry_run:)
    @schema             = Schema.find schema_id
    @user_options       = user_options
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

end