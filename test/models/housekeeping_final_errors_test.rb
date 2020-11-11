require 'test_helper'

class HousekeepingFinalErrorsTest < ActiveSupport::TestCase

  test "do_housekeeping" do
    retval = HousekeepingFinalErrors.get_instance.do_housekeeping
    assert(retval, 'Should not return false')

    record_count = Database.select_one "SELECT COUNT(*) FROM Event_Log_Final_Errors"
    assert_equal 1, record_count, 'Only younger record from fixtures should survive housekeeping'
  end

end
