class User < ApplicationRecord
  has_many :activity_logs
  has_many :schema_rights
  validate :validate_schema_name
  validates :yn_admin, acceptance: { accept: ['Y', 'N'] }

  def validate_schema_name
    self.db_user = db_user.upcase if Trixx::Application.config.trixx_db_type == 'ORACLE' && !db_user.nil?
    unless DbSchema.valid_schema_name?(db_user)
      errors.add(:db_user, "User '#{db_user}' does not exists in database")
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

  MAX_FAILED_LOGONS = 5
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
  rescue Exception => e
    self.update!(yn_account_locked: 'Y')
    ActivityLog.new(user_id: self.id, action: 'User locked at delete request because foreign keys prevent the deletion').save!
  end
end
