require 'test_helper'

class EventLogTest < ActiveSupport::TestCase

  test "create event log" do
    EventLog.new(table_id: 1, operation: 'I', dbuser: 'HUGO', payload: 'Payload').save!
  end

  test "select event log" do
    event_logs = EventLog.all
  end

end
