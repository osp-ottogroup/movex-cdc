class DatabaseSqlite

# Set context info
  def self.set_application_info(action_info)
    # no implementation for SQLite
  end

  def self.db_version
    'SQLite'
  end

  def self.jdbc_driver_version
    'SQLite driver'
  end

  def self.jdbc_driver_path
    "SQLite driver path"
  end

  def self.db_default_timezone
    '+00:00'
  end
end