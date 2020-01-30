require 'test_helper'

class TriggerTest < ActiveSupport::TestCase

  setup do
    # Create victim tables and triggers
    create_victim_structures
  end

  teardown do
    # Remove victim structures
    drop_victim_structures
  end

  test "find_all_by_schema_id" do
    triggers = DbTrigger.find_all_by_schema_id(victim_schema_id)
    assert_equal(2, triggers.count, 'Should find the number of triggers in victim schema')
  end

  test "find_by_table_id_and_trigger_name" do
    trigger = DbTrigger.find_by_table_id_and_trigger_name(4, 'Trixx_Victim1_I')
    assert_not_equal(nil, trigger, 'Should find the trigger in victim schema')
  end

  test "generate_triggers" do
    result = DbTrigger.generate_triggers(victim_schema_id)
  end

end
