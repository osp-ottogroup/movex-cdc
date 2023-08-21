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

      db_version_gt_12_1 = select_single conn, "SELECT CASE WHEN Version < '12.2' THEN 0 ELSE 1 END FROM v$Instance"
      if db_version_gt_12_1 == 1
        # Speed up execution in smaller test DBs
        # in 12.1: ORA-65040: operation not allowed from within a pluggable database
        #exec conn, "ALTER SYSTEM SET parallel_max_servers=0 SCOPE=BOTH"
      end

      # exclude "X$COMVW$" from execution plan
      # see also: Dictionary Queries Run Slowly in 12C Pluggable Databases (Doc ID 2033658.1)
      # https://support.oracle.com/epmos/faces/DocumentDisplay?_afrLoop=471348295695682&parent=EXTERNAL_SEARCH&sourceId=PROBLEM&id=2033658.1&_afrWindowMode=0&_adf.ctrl-state=dywy3nphu_4

      exec conn, 'ALTER SYSTEM SET "_common_data_view_enabled"=false SCOPE=BOTH'
      conn.close
    end

  end
end