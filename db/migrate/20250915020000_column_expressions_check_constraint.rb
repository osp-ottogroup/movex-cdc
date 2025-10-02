class ColumnExpressionsCheckConstraint < ActiveRecord::Migration[6.0]

  # create primary key constraint for test, otherwise loading fixtures will result in error
  def up
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      EventLog.connection.execute("ALTER TABLE Column_Expressions ADD Constraint CK_Column_Expr_Operation CHECK (Operation IN ('I', 'U', 'D'))")
    end
  end

  def down
    sql = "ALTER TABLE Column_Expressions DROP Constraint CK_Column_Expr_Operation"
    EventLog.connection.execute(sql)
  rescue Exception => e
    puts "Error: #{e.message}\nwhile executing:\n#{sql}"
  end

end
