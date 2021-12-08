# get available schemas of database
class DbSchema

  # get all existings users/schemas
  def self.all
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      ActiveRecord::Base.connection.exec_query("SELECT UserName name FROM All_Users ORDER BY UserName")
    when 'SQLITE' then
      [{ 'name' => 'main'}]
    end
  end

  # delivers filtered list of schemas where the db_user has read grants on at least one table
  # schemas already attached to the user are not listed again
  # email or db_user may be nil
  def self.authorizable_schemas(email, db_user)
    users = User.where email: email
    user = users.count > 0 ? users[0] : nil

    db_user = user&.db_user if db_user.nil?                                     # one of both should be set with real values, user users db_user as alternative

    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      Database.select_all("\
        SELECT Name
        FROM   (SELECT DISTINCT Owner Name FROM Allowed_DB_Tables WHERE Grantee = :user_name )
        MINUS
        SELECT UPPER(s.Name)
        FROM   Schemas s
        JOIN   Schema_Rights sr ON sr.Schema_ID = s.ID
        WHERE  sr.User_ID = :user_id
        ORDER BY Name
        ", { user_name: db_user, user_id: user&.id
      }
      )
    when 'SQLITE' then
      authorizedSchema = Database.select_all(
                        "SELECT schema_id
                             FROM Schema_Rights
                             WHERE  user_id = :user_id",
                        { user_id: user&.id})
      if authorizedSchema.count == 0 # user is not authorized for schema 'main'
        [ 'name' => 'main']
      else
        []                     # user is already authorized for schema 'main'
      end
    end
  end

  # Check schema name for existence, case independent
  def self.valid_schema_name?(schema_name)
    return false if schema_name.nil?
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      Database.select_one("SELECT COUNT(*) FROM All_Users WHERE UserName = :schema_name", {schema_name: schema_name}) > 0
    when 'SQLITE' then
      schema_name.downcase == 'main'
    end
  end
end
