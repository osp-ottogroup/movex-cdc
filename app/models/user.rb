class User < ApplicationRecord
  has_many :activity_logs
  has_many :schema_rights
  validate :validate_values
  # validates :yn_admin, acceptance: { accept: ['Y', 'N'] }

  def validate_values
    validate_yn_column :yn_admin
    validate_yn_column :yn_account_locked
    validate_yn_column :yn_hidden

    self.db_user = db_user.upcase if Trixx::Application.config.trixx_db_type == 'ORACLE' && !db_user.nil?
    unless DbSchema.valid_schema_name?(db_user)
      errors.add(:db_user, "User '#{db_user}' does not exists in database")
    end

    # reset failed logons if user becomes unlocked
    unless self.id.nil?                                                         # unsaved created user
      prev_values = User.find self.id
      if prev_values&.yn_account_locked == 'Y' && self.yn_account_locked == 'N' # chenge of locked state
        self.failed_logons = 0                                                  # start with no failed logons after unlock
      end
    end
  end

  def self.find_by_email_case_insensitive(email)
    users = find_by_sql "SELECT * FROM Users WHERE UPPER(Email) = UPPER(:email)",
                        [ActiveRecord::Relation::QueryAttribute.new(':email', email, ActiveRecord::Type::Value.new)]
    users.count == 0 ? nil : users[0]
  end

  def self.find_by_db_user_case_insensitive(db_user)
    users = find_by_sql "SELECT * FROM Users WHERE UPPER(DB_User) = UPPER(:db_user)",
                        [ActiveRecord::Relation::QueryAttribute.new(':db_user', db_user, ActiveRecord::Type::Value.new)]
    users.count == 0 ? nil : users[0]
  end

  def self.count_by_db_user_case_insensitive(db_user)
    result = find_by_sql "SELECT COUNT(*) amount FROM Users WHERE UPPER(DB_User) = UPPER(:db_user)",
                        [ActiveRecord::Relation::QueryAttribute.new(':db_user', db_user, ActiveRecord::Type::Value.new)]
    result[0].amount
  end

  MAX_FAILED_LOGONS = 3                                                         # should be small enough to prevent DB account from beeing locked
  def increment_failed_logons
    self.failed_logons = self.failed_logons + 1
    self.yn_account_locked='Y' if self.failed_logons >= MAX_FAILED_LOGONS
    save!
  end

  def reset_failed_logons
    self.failed_logons = 0
    save!
  end

  def destroy
    super
    :destroyed
  rescue ActiveRecord::StaleObjectError
    raise
  rescue Exception => e
    # Lock user in case DELETE is not possbible due to constraint violation
    self.update!(yn_account_locked: 'Y', yn_hidden: 'Y')
    :locked
  end

  # Check and raise exception if no right available
  def check_user_for_valid_schema_right(schema_id)
    raise "Missing parameter schema_id for check of schema_rights for user '#{self.email}'" if schema_id.nil?
    schema_right = self.schema_rights.where(schema_id: schema_id).first
    # schema_right = SchemaRight.find_by_user_id_and_schema_id(@current_user.id, schema_id)
    if schema_right.nil?
      schema = Schema.where(id: schema_id).first
      raise "User '#{self.email}' has no right for schema '#{schema&.name}'"
    end
    schema_right
  end

end
