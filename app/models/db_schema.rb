# get available schemas of database
class DbSchema

  # get all existings users/schemas
  def self.all
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      ActiveRecord::Base.connection.exec_query("SELECT UserName name FROM All_Users")
    when 'SQLITE' then
      [{ 'name' => 'main'}]
    end
  end

  # delivers filtered list of schemas really owning tables
  # schemas already attached to the user are not listed again
  def self.remaining_schemas(email)
     users = User.where email: email
    user = users.count > 0 ? users[0] : nil

    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      TableLess.select_all("SELECT DISTINCT Owner Name FROM DBA_Tables
                            MINUS
                            SELECT UPPER(s.Name)
                            FROM   Schemas s
                            JOIN   Schema_Rights sr ON sr.Schema_ID = s.ID
                            WHERE  sr.User_ID = :user_id
                           ", { user_id: user&.id}
      )
    when 'SQLITE' then
      if user.nil?                                                              # Full list for not existing user
        [ 'name' => 'main']
      else
        []                                                                      # 'main' should be excluded because it is in Schema_Rights
      end
    end
  end

  # Check schema name for existence, case independent
  def self.valid_schema_name?(schema_name)
    return false if schema_name.nil?
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      TableLess.select_one("SELECT COUNT(*) FROM All_Users WHERE UserName = :schema_name", { schema_name: schema_name.upcase}) > 0
    when 'SQLITE' then
      schema_name == 'main'
    end
  end
end
