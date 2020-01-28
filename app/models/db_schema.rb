# get available schemas of database
class DbSchema

  def self.all
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      ActiveRecord::Base.connection.exec_query("SELECT UserName Name FROM All_Users")
    when 'SQLITE' then
      [{ 'name' => 'main'}]
    end
  end
end
