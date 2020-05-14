require 'test_helper'

class EventLogTest < ActiveSupport::TestCase

  test "create event log" do
    EventLog.new(table_id: 1, operation: 'I', dbuser: 'HUGO', payload: 'Payload').save!
  end

  test "select event log" do
    create_event_logs_for_test(2)
    event_logs = EventLog.all
    assert(event_logs.count > 0, 'Should return at least one record')
  end

end
