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
  def self.authorizable_schemas(email)
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
end
