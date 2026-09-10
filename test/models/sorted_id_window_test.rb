require 'test_helper'

class SortedIdWindowTest < ActiveSupport::TestCase
  MAX_TRANSACTION_SIZE = 100                                                    # small value to keep the expected numbers readable

  def new_window(partition_name: nil)
    SortedIdWindow.new(max_transaction_size: MAX_TRANSACTION_SIZE, partition_name: partition_name)
  end

  test "initial distance ensures less than max_transaction_size records per read" do
    assert_equal MAX_TRANSACTION_SIZE-1, new_window.distance
    assert_equal MAX_TRANSACTION_SIZE-1, new_window(partition_name: 'EVENT_LOGS_P1').distance
  end

  test "window is not shrinkable as long as a read cannot exceed max_transaction_size" do
    window = new_window
    assert_not window.shrinkable?, 'Initial distance must not allow more than max_transaction_size records'
    window.grow(read_count: 0)                                                  # enlarge beyond max_transaction_size
    assert window.shrinkable?, "Distance #{window.distance} above max_transaction_size must be shrinkable"
  end

  test "shrink_to_fit reduces distance so that the next read starts below max_transaction_size records" do
    window = new_window
    window.grow(read_count: 0)                                                  # 99 -> (99+1)*10 = 1000

    # lowest read ID 500 with a read based on ID 400: 500 + 100*0.9 - 400 - 1
    assert_equal 189, window.shrink_to_fit(lowest_read_id: 500, base_id: 400)
    assert_equal 189, window.distance
  end

  test "shrink_to_fit falls back to initial distance if the calculation is unusable" do
    window = new_window
    window.grow(read_count: 0)

    # lowest read ID below the base ID yields a negative distance, which must be discarded
    assert_equal MAX_TRANSACTION_SIZE-1, window.shrink_to_fit(lowest_read_id: 400, base_id: 500)
    assert_equal MAX_TRANSACTION_SIZE-1, window.distance
  end

  test "growth is only useful if less than a third of max_transaction_size was read" do
    window = new_window
    assert     window.growth_useful?(read_count: 0)
    assert     window.growth_useful?(read_count: MAX_TRANSACTION_SIZE/3 - 1)
    assert_not window.growth_useful?(read_count: MAX_TRANSACTION_SIZE/3)
    assert_not window.growth_useful?(read_count: MAX_TRANSACTION_SIZE)
  end

  test "grow enlarges aggressively if nothing was read at all" do
    window = new_window
    assert_equal (MAX_TRANSACTION_SIZE-1 + 1) * 10, window.grow(read_count: 0)
  end

  test "grow scales with the unused part of max_transaction_size" do
    # half of max_transaction_size read -> factor 1, so the distance stays nearly unchanged
    window = new_window
    assert_equal MAX_TRANSACTION_SIZE, window.grow(read_count: MAX_TRANSACTION_SIZE/2)

    # a quarter read -> factor 2
    window = new_window
    assert_equal MAX_TRANSACTION_SIZE*2, window.grow(read_count: MAX_TRANSACTION_SIZE/4)

    # a single record read -> factor close to the maximum of 3
    window = new_window
    assert_operator window.grow(read_count: 1), :<=, MAX_TRANSACTION_SIZE*3
    assert_operator window.distance, :>, MAX_TRANSACTION_SIZE*2
  end

  test "reset restores the initial distance" do
    window = new_window
    window.grow(read_count: 0)
    assert_not_equal MAX_TRANSACTION_SIZE-1, window.distance
    window.reset
    assert_equal MAX_TRANSACTION_SIZE-1, window.distance
  end
end
