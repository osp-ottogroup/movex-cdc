class DbTriggerGeneratorBase < Database
  attr_reader :successes, :errors, :load_sqls
  TRIGGER_NAME_PREFIX = "TRIXX_"                                                # owner of trigger is always trixx_db_user, must not be part of trigger name

  ### class methods following

  # generate trigger name from short operation (I/U/D) and schema/table
  def self.build_trigger_name(table, operation)
    # Ensure trigger name remains unique even if schema or table IDs change (e.g. after export + reimport)
    "#{TRIGGER_NAME_PREFIX}#{operation}_#{table.schema.id}_#{table.id}_#{table.schema.name.sum}_#{table.name.sum}"
  end

  ### instance methods following

  def initialize(schema_id:, user_options:, dry_run:)
    @schema       = Schema.find schema_id
    @user_options = user_options
    @dry_run      = dry_run
    @successes    = []                                                          # created triggers
    @errors       = []                                                          # errors during trigger creation
    @load_sqls    = []                                                          # PL/SQL snipped for initial load
  end
end