# get available schemas of database
class DbSchema

  # get all existings users/schemas
  def self.all
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      ActiveRecord::Base.connection.exec_query("SELECT UserName name FROM All_Users ORDER BY UserName")
    when 'SQLITE' then
      [{ 'name' => 'main'}]
    end
  end

  # delivers filtered list of schemas really owning tables
  # schemas already attached to the user are not listed again
  def self.authorizable_schemas(email)
    users = User.where email: email
    user = users.count > 0 ? users[0] : nil

    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      TableLess.select_all("\
        SELECT Name
        FROM   (SELECT Owner Name FROM DBA_Tables WHERE Owner = :user_name1 AND RowNum < 2 /* Own schema has tables */
                UNION
                /* Explicite table grants for user */
                SELECT DISTINCT Owner
                FROM   DBA_TAB_PRIVS
                WHERE  Privilege = 'SELECT'
                AND    Type = 'TABLE'
                AND    Grantee = :user_name2
                UNION
                /* All schemas with tables if user has SELECT ANY TABLE */
                SELECT DISTINCT Owner Name FROM DBA_Tables WHERE EXISTS (SELECT 1 FROM DBA_Sys_Privs WHERE Privilege = 'SELECT ANY TABLE' AND Grantee = :user_name3)
               )
        MINUS
        SELECT UPPER(s.Name)
        FROM   Schemas s
        JOIN   Schema_Rights sr ON sr.Schema_ID = s.ID
        WHERE  sr.User_ID = :user_id
        ORDER BY Name
        ", { user_name1: user&.db_user&.upcase,
             user_name2: user&.db_user&.upcase,
             user_name3: user&.db_user&.upcase,
             user_id: user&.id
      }
      )
    when 'SQLITE' then
      authorizedSchema = TableLess.select_all(
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
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      TableLess.select_one("SELECT COUNT(*) FROM All_Users WHERE UserName = :schema_name", { schema_name: schema_name.upcase}) > 0
    when 'SQLITE' then
      schema_name.downcase == 'main'
    end
  end
end
