require 'test_helper'

class EventLogTest < ActiveSupport::TestCase

  test "create event log" do
    EventLog.new(schema_id: 1, table_id: 1, operation: 'I', payload: 'Payload').save!
  end

  test "select event log" do
    event_logs = EventLog.all
    assert(event_logs.count > 0, 'Should return at least one record')
  end

end
