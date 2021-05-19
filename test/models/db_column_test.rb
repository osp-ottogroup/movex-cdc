require 'test_helper'

class DbColumnTest < ActiveSupport::TestCase

  test "get db columns" do
    db_columns = DbColumn.all_by_table(Trixx::Application.config.trixx_db_user, 'TABLES')
    assert(db_columns.count > 0, 'Should get at least one column of table')
  end

end
