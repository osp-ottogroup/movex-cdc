require 'test_helper'

class HousekeepingFinalErrorsTest < ActiveSupport::TestCase

  test "do_housekeeping" do
    Database.execute "DELETE FROM Event_Log_Final_Errors"
    Database.execute "INSERT INTO Event_Log_Final_Errors (ID, Table_ID, Operation, DBUser, Payload, Created_At, Error_Time, Error_Msg)
                    VALUES (-1, 1, 'I', 'HUGO', '{}', :created_at, :error_time, 'Test-Error to delete')
                   ", binds: {created_at: 100.day.ago, error_time: 100.day.ago}
    Database.execute "INSERT INTO Event_Log_Final_Errors (ID, Table_ID, Operation, DBUser, Payload, Created_At, Error_Time, Error_Msg)
                    VALUES (-2, 1, 'I', 'HUGO', '{}', :created_at, :error_time, 'Test-Error to keep')
                   ", binds: {created_at: 100.day.ago, error_time: 2.day.ago}

    # Ensure the previous Inserts are really commited in test environment! ActiveRecord::Base.transaction does not do this in test environment.
    Database.execute "COMMIT" if MovexCdc::Application.config.db_type == 'ORACLE'

    retval = HousekeepingFinalErrors.get_instance.do_housekeeping
    assert retval, log_on_failure('Should not return false')

    record_count = Database.select_one "SELECT COUNT(*) FROM Event_Log_Final_Errors"
    assert_equal 1, record_count, log_on_failure('Only younger record from fixtures should survive housekeeping')
    Database.execute "DELETE FROM Event_Log_Final_Errors"
  end

end
