namespace :ci_preparation do
  desc "Prepare test tables of victim user for running tests in CI pipeline"

  task :reset_test_tables do

    def exec(conn, sql)
      puts "Execute: #{sql}"
      stmt = conn.prepareStatement(sql)
      stmt.executeUpdate
    ensure
      stmt.close rescue nil
    end

    def select_single(conn, sql)
      stmt = conn.prepareStatement(sql);
      resultSet = stmt.executeQuery(sql);
      resultSet.next
      result = resultSet.getInt(1)
      result
    ensure
      resultSet.close rescue nil
      stmt.close rescue nil
    end

    # Recreate table
    def reset_table(connection, table_name, columns)
      begin
        exec(connection, "DROP TABLE #{table_name}")
      rescue Exception => e
        raise if !e.message['ORA-00942']                                        # catch exception only if "Tabelle oder View nicht vorhanden"
      end

      sql = "CREATE TABLE #{table_name} (\n"
      col_count = 0
      columns.each do |col|
        col_count += 1
        sql << ",\n" if col_count > 1
        sql << "#{col[:name]} #{col[:type]}"
        sql << "(#{col[:precision]})" if col.has_key?(:precision)
      end
      sql << "\n)"
      exec(connection, sql)
    end

    puts "Running ci_preparation:create_user for db_type = #{MovexCdc::Application.config.db_type }"

    # create JDBC-connection related to DB-Type
    conn = case MovexCdc::Application.config.db_type
           when 'ORACLE' then
             java.sql.DriverManager.getConnection("jdbc:oracle:thin:#{MovexCdc::Application.config.db_victim_user}/#{MovexCdc::Application.config.db_victim_password}@#{MovexCdc::Application.config.db_url}")
           end

    reset_table(conn, 'Test_Table1', [
        { name: 'ID',         type: 'NUMBER',   precision: 8 },
        { name: 'Col1',       type: 'VARCHAR2', precision: 20 },
    ])

    conn.close                                                                  # close JDBC-Connection

  end
end