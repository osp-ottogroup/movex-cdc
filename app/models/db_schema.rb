# get available schemas of database
class DbSchema

  # delivers filtered list of schemas really owning tables
  # schemas already attached to the user are not listed again
  def self.remaining_schemas(current_user)
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      TableLess.select_all("SELECT DISTINCT Owner Name FROM DBA_Tables
                            MINUS
                            SELECT s.Name
                            FROM   Schemas s
                            JOIN   Schema_Rights sr ON sr.Schema_ID = s.ID
                            WHERE  sr.User_ID = :user_id
                           ", { user_id: current_user.id}
      )
    when 'SQLITE' then
      [{ 'name' => 'main'}]
    end
  end
end
