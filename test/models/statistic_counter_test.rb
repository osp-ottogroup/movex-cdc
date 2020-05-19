require 'test_helper'

class StatisticCounterTest < ActiveSupport::TestCase
  test "create statistics" do
    sc = StatisticCounter.new

    sc.increment(tables(:one).id, 'I')
    sc.increment(tables(:one).id, 'I')
    sc.increment(tables(:two).id, 'I')
    sc.increment(tables(:one).id, 'D')
    sc.increment(tables(:two).id, 'U')
    sc.increment(tables(:two).id, 'U')
    sc.increment(tables(:two).id, 'D')

    sc.flush_success

    assert_equal 2,   TableLess.select_one("SELECT SUM(Events_Success) FROM Statistics WHERE Table_ID = 1 AND Operation = 'I'"), 'Table 1 inserts success'
    assert_equal 1,   TableLess.select_one("SELECT SUM(Events_Success) FROM Statistics WHERE Table_ID = 2 AND Operation = 'I'"), 'Table 2 inserts success'

    assert_equal nil, TableLess.select_one("SELECT SUM(Events_Success) FROM Statistics WHERE Table_ID = 1 AND Operation = 'U'"), 'Table 1 updates success'
    assert_equal 2,   TableLess.select_one("SELECT SUM(Events_Success) FROM Statistics WHERE Table_ID = 2 AND Operation = 'U'"), 'Table 2 updates success'

    assert_equal 1,   TableLess.select_one("SELECT SUM(Events_Success) FROM Statistics WHERE Table_ID = 1 AND Operation = 'D'"), 'Table 1 updates deletes'
    assert_equal 1,   TableLess.select_one("SELECT SUM(Events_Success) FROM Statistics WHERE Table_ID = 2 AND Operation = 'D'"), 'Table 2 updates deletes'

    sc.increment(tables(:one).id, 'I')
    sc.increment(tables(:one).id, 'I')
    sc.increment(tables(:two).id, 'I')
    sc.increment(tables(:one).id, 'D')
    sc.increment(tables(:two).id, 'U')
    sc.increment(tables(:two).id, 'U')
    sc.increment(tables(:two).id, 'D')

    sc.flush_failure

    assert_equal 2,   TableLess.select_one("SELECT SUM(Events_Failure) FROM Statistics WHERE Table_ID = 1 AND Operation = 'I'"), 'Table 1 inserts failure'
    assert_equal 1,   TableLess.select_one("SELECT SUM(Events_Failure) FROM Statistics WHERE Table_ID = 2 AND Operation = 'I'"), 'Table 2 inserts failure'

    assert_equal nil, TableLess.select_one("SELECT SUM(Events_Failure) FROM Statistics WHERE Table_ID = 1 AND Operation = 'U'"), 'Table 1 updates failure'
    assert_equal 2,   TableLess.select_one("SELECT SUM(Events_Failure) FROM Statistics WHERE Table_ID = 2 AND Operation = 'U'"), 'Table 2 updates failure'

    assert_equal 1,   TableLess.select_one("SELECT SUM(Events_Failure) FROM Statistics WHERE Table_ID = 1 AND Operation = 'D'"), 'Table 1 updates failure'
    assert_equal 1,   TableLess.select_one("SELECT SUM(Events_Failure) FROM Statistics WHERE Table_ID = 2 AND Operation = 'D'"), 'Table 2 updates failure'


  end

end
