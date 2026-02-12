require_relative '../../app/models/database_oracle'

namespace :ci_preparation do
  desc "Disable parallel query to ensure performance with Docker container and less CPU ressources.
Access to dictionary views has massively slowed down in PDB environments while using PQ.
  "

  task :speedup_oracle_dictionary_calls do

    def exec(conn, sql)
      puts "Execute: #{sql}"
      stmt = conn.prepareStatement(sql)
      stmt.executeUpdate
    ensure
      stmt.close rescue nil
    end

    def select_single(conn, sql)
      # puts "Execute: #{sql}"
      stmt = conn.prepareStatement(sql);
      resultSet = stmt.executeQuery(sql);
      resultSet.next
      result = resultSet.getInt(1)
      result
    ensure
      resultSet.close rescue nil
      stmt.close rescue nil
    end

    puts "Running ci_preparation:speedup_oracle_dictionary_calls for db_type = #{MovexCdc::Application.config.db_type }"
    if MovexCdc::Application.config.db_type == 'ORACLE'
      conn = DatabaseOracle.connect_as_sys_user

      # exclude "X$COMVW$" from execution plan
      # see also: Dictionary Queries Run Slowly in 12C Pluggable Databases (Doc ID 2033658.1)
      # https://support.oracle.com/epmos/faces/DocumentDisplay?_afrLoop=471348295695682&parent=EXTERNAL_SEARCH&sourceId=PROBLEM&id=2033658.1&_afrWindowMode=0&_adf.ctrl-state=dywy3nphu_4

      exec conn, 'ALTER SYSTEM SET "_common_data_view_enabled"=false SCOPE=BOTH'
      conn.close
    end

  end
end