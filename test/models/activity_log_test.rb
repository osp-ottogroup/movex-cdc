require 'test_helper'

class ActivityLogTest < ActiveSupport::TestCase

  test "create activity_log" do
    ActivityLog.new(user_id: peter_user.id, schema_name: 'Schema1', table_name: 'Table1', column_name: 'Column1', action: 'info').save!
    ActivityLog.new(user_id: peter_user.id, schema_name: 'Schema1', table_name: 'Table1', action: 'Without column').save!
    ActivityLog.new(user_id: peter_user.id, schema_name: 'Schema1', action: 'Without table').save!
  end

end
