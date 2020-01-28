require 'test_helper'

class ActivityLogTest < ActiveSupport::TestCase

  test "create activity_log" do
    ActivityLog.new(user_id: 1, schema_name: 'Schema1', table_name: 'Table1', column_name: 'Column1', action: 'info').save!
  end

end
