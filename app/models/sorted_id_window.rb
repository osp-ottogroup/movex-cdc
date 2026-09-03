# Adaptive upper limit for the range of Event_Logs.ID that TransferThread reads at once
# in step 1 of read_event_logs_steps (the events with Msg_Key).
#
# Background: a single SELECT must never return more than max_transaction_size records.
# If it does, it is not ensured that all records with smaller IDs have been read already.
# That would break the processing order by ID, which has to be guaranteed for events sharing a Msg_Key.
#
# The upper bound of the next SELECT is therefore 'start ID + distance', where the distance
# is tuned at runtime based on the outcome of the previous read:
# - shrink_to_fit  after a read that hit the limit of max_transaction_size records
# - grow           after a read that used less than a third of that limit
#
# One instance exists per Event_Logs partition, partition_name is nil for non-partitioned tables.
class SortedIdWindow
  attr_reader :distance

  # @param max_transaction_size [Integer] max. number of records read and processed at once by the worker thread
  # @param partition_name [String, nil] name of the Event_Logs partition this window belongs to
  def initialize(max_transaction_size:, partition_name: nil)
    @max_transaction_size = max_transaction_size
    @partition_name       = partition_name
    reset
    Rails.logger.debug('SortedIdWindow.initialize'){ "Initializing max_sorted_id_distance#{partition_suffix} to #{@distance}" }
  end

  # Set the largest distance that still ensures less than max_transaction_size records are read at once
  # @return [Integer] the new distance
  def reset
    @distance = @max_transaction_size - 1
  end

  # Is the window still large enough to be reduced?
  # If not, the caller has to lower the start ID of the next read instead,
  # because there are more than max_transaction_size records within the smallest possible window.
  # @return [Boolean]
  def shrinkable?
    @distance >= @max_transaction_size
  end

  # Reduce the distance so that the next read returns less than max_transaction_size records but still more than none.
  # Falls back to the initial distance if the calculation yields an unusable value.
  # @param lowest_read_id [Integer] smallest Event_Logs.ID of the discarded read result
  # @param base_id [Integer] the start ID the discarded read was based on
  # @return [Integer] the new distance
  def shrink_to_fit(lowest_read_id:, base_id:)
    new_distance = (lowest_read_id + @max_transaction_size * 0.9 - base_id - 1).to_i
    if new_distance < 1                                                         # suppress negative results that may be possible in some circumstances
      # This leads to a recalculation of the caller's start ID at next loop if the result size is still too large
      Rails.logger.debug('SortedIdWindow.shrink_to_fit'){ "calculation of max_sorted_id_distance discarded (#{new_distance})#{partition_suffix}" }
      reset
    else
      @distance = new_distance
    end
    Rails.logger.debug('SortedIdWindow.shrink_to_fit'){ "max_sorted_id_distance decreased to #{@distance}#{partition_suffix} because the number of read events should be less than #{@max_transaction_size}" }
    @distance
  end

  # Did the last read use so few of the allowed records that enlarging the window is worth a try?
  # @param read_count [Integer] number of records returned by the last read
  # @return [Boolean]
  def growth_useful?(read_count:)
    read_count < @max_transaction_size / 3
  end

  # Enlarge the distance because the last read used only a small part of max_transaction_size
  # @param read_count [Integer] number of records returned by the last read
  # @return [Integer] the new distance
  def grow(read_count:)
    increase_factor = growth_factor(read_count)
    @distance = ((@distance + 1) * increase_factor).to_i
    Rails.logger.debug('SortedIdWindow.grow'){ "max_sorted_id_distance increased by factor #{increase_factor} to #{@distance}#{partition_suffix}" }
    @distance
  end

  private

  # Scored factor from 1 up to 3 depending on how much of max_transaction_size was used by the last read
  # @param read_count [Integer] number of records returned by the last read
  # @return [Numeric] the factor to enlarge the distance with
  def growth_factor(read_count)
    return 10 if read_count == 0                                                # nothing found in this range at all, so enlarge aggressively
    1 + (@max_transaction_size/2.0 - read_count) * 2 / (@max_transaction_size/2.0)
  end

  # @return [String, nil] suffix for log messages naming the partition, nil for non-partitioned tables
  def partition_suffix
    " for partition #{@partition_name}" if @partition_name
  end
end
