require 'test_helper'

class TableInitializationTest < ActiveSupport::TestCase
  setup do
    # Create victim tables and triggers
    create_victim_structures
  end

  test "get_instance" do
    instance = TableInitialization.get_instance
    assert instance.instance_of?(TableInitialization), 'should return instance of class'
  end


end

