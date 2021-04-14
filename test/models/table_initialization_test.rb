require 'test_helper'

class TableInitializationTest < ActiveSupport::TestCase
  setup do
    # Create victim tables and triggers
    @victim_connection = create_victim_connection
    create_victim_structures(@victim_connection)
  end

  teardown do
    # Remove victim structures
    drop_victim_structures(@victim_connection)
    logoff_victim_connection(@victim_connection)
  end

  test "get_instance" do
    instance = TableInitialization.get_instance
    assert instance.instance_of?(TableInitialization), 'should return instance of class'
  end


end

