require 'test_helper'

class EventLogFinalErrorTest < ActiveSupport::TestCase

  # create and rollback one record to provoke partition creation
  test "final_error_count" do
    max_error_count = 5
    final_error_count = Database.select_one "SELECT COUNT(*) FROM #{MovexCdc::Application.config.db_user}.Event_Log_Final_Errors"
    final_error_count = max_error_count if final_error_count > max_error_count
    test_count = EventLogFinalError.final_error_count(max_count: max_error_count)
    assert final_error_count == test_count, log_on_failure("Final error count should be #{final_error_count } but is #{test_count} instead")
  end

  test "an_error_message" do
    assert_nothing_raised do
      EventLogFinalError.an_error_message
    end
  end
end
