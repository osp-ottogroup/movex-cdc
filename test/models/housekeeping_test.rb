require 'test_helper'

class HousekeepingTest < ActiveSupport::TestCase

  test "do_housekeeping" do
    retval = Housekeeping.get_instance.do_housekeeping
    assert(retval, 'Should not return false')
  end

end
