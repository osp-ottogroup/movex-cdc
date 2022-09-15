class User < ApplicationRecord
  has_many :activity_logs
  has_many :schema_rights
  has_many :schemas, through: :schema_rights
  validate :validate_values
  # validates :yn_admin, acceptance: { accept: ['Y', 'N'] }

  def validate_values
    validate_yn_column :yn_admin
    validate_yn_column :yn_account_locked
    validate_yn_column :yn_hidden

    self.db_user = db_user.upcase if MovexCdc::Application.config.db_type == 'ORACLE' && !db_user.nil?
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

  # system initialization has finished if table Users exists and admin account exists
  def self.check_for_system_init_completed
    result = Database.select_one "SELECT COUNT(*) FROM Users WHERE EMail = :email", email: 'admin'
    raise "User 'admin' does not exist in table Users" if result == 0
  rescue Exception => e
    raise "System initialization not yet finished!\nPlease retry later or restart system if problem persists!\nReason: #{e.class}:#{e.message}"
  end

  def increment_failed_logons
    self.failed_logons = self.failed_logons + 1 if self.failed_logons < 99      # remember only the first 99 failed logons because of number(2)
    self.yn_account_locked='Y' if self.failed_logons >= MovexCdc::Application.config.max_failed_logons_before_account_locked
    save!                                                                       # explicite usage of save! instead of update!
  end

  def lock_account
    update!(yn_account_locked: 'Y')
  end

  def reset_failed_logons
    update!(failed_logons: 0)
  end

  def destroy
    Rails.logger.warn('User.destroy') { "primary user 'admin' should never be deleted!" } if self.email == 'admin'
    super
    :destroyed
  rescue ActiveRecord::StaleObjectError
    raise
  rescue Exception => e
    # Lock user in case DELETE is not possbible due to constraint violation
    Rails.logger.debug('User.destroy'){"#{e.class} '#{e.message}' during delete of user. Setting account locked instead."}
    User.find(self.id).update!(yn_account_locked: 'Y', yn_hidden: 'Y') # Update new User object because original object is frozen after failed delete
    :locked
  end

  # Check and raise exception if no right available
  def check_user_for_valid_schema_right(schema_id)
    raise "Missing parameter schema_id for check of schema_rights for user '#{self.email}'" if schema_id.nil?
    schema_right = self.schema_rights.where(schema_id: schema_id).first
    if schema_right.nil?
      schema = Schema.where(id: schema_id).first
      raise "User '#{self.email}' has no right for schema '#{schema&.name}'"
    end
    schema_right
  end

  def deployable_schemas
    self.schemas.where(:schema_rights => {yn_deployment_granted: 'Y'})
  end

  def can_deploy_schemas?
    self.deployable_schemas.count > 0
  end

  # get hash with schema_name, table_name, column_name for activity_log
  def activity_structure_attributes
    {}
  end
end
