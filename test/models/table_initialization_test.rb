require 'test_helper'

class TableInitializationTest < ActiveSupport::TestCase
  setup do
    # Create victim tables and triggers
    create_victim_structures
  end

  test "get_instance" do
    instance = TableInitialization.get_instance
    assert instance.instance_of?(TableInitialization), 'should return instance of class'
  end

  test "add_table_initialization" do
    sql = case MovexCdc::Application.config.db_type
          when 'ORACLE' then
            "BEGIN\nNULL;\nEND;"
          when 'SQLITE' then
            "\
INSERT INTO Event_Logs(Table_ID, Operation, DBUser, Created_At, Payload, Msg_Key)
SELECT #{victim1_table.id}, 'I', 'main', strftime('%Y-%m-%d %H-%M-%f','now'), '\"new\": {}', 'N',
FROM   main.#{victim1_table.name}
            "
          end

    ti_instance = TableInitialization.get_instance
    ti_instance.add_table_initialization(victim1_table.id, victim1_table.name, sql, user_options_4_test)
    assert_equal(0, ti_instance.init_requests_count(raise_exception_if_locked: false), 'Request should not be waiting')
    assert_equal(1, ti_instance.running_threads_count(raise_exception_if_locked: false), 'Request should be running now')
    sleep 1
    max_loop = 0
    while (ti_instance.init_requests_count(raise_exception_if_locked: false) > 0 ||
      ti_instance.running_threads_count(raise_exception_if_locked: false) > 0 ) &&
      max_loop < 20
      max_loop += 1
      sleep 1
    end

    assert_equal(0, ti_instance.init_requests_count(raise_exception_if_locked: false), 'All requests should be started')
    assert_equal(0, ti_instance.running_threads_count(raise_exception_if_locked: false), 'All requests should be finished')

  end


end

