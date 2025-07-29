# This Job runs repeats itself permanent and runs once each day
class DailyJob < ApplicationJob
  queue_as :default
  CYCLE = 86400

  def perform(*args)
    DailyJob.set(wait: CYCLE.seconds).perform_later unless Rails.env.test?  # Ensure next execution independent from following operations
    reset_job_warnings(CYCLE)

    # do housekeeping activities
    begin
      Database.set_application_info('DailyJob/CompressStatistics.do_compress')
      CompressStatistics.get_instance.do_compress
    rescue Exception => e
      ExceptionHelper.log_exception(e, 'HourlyJob.perform', additional_msg: "calling CompressStatistics.do_compress!\n#{ExceptionHelper.memory_info_hash}")
      add_execption_to_job_warning(e)
      Database.close_db_connection                                              # Physically disconnect the DB connection of this thread, so that next request in this thread will re-open the connection again
    end

    begin
      Database.set_application_info('DailyJob/Housekeeping.check_partition_interval')
      Housekeeping.get_instance.check_partition_interval                        # update high value of first partition if necessary
    rescue Exception => e
      ExceptionHelper.log_exception(e, 'HourlyJob.perform', additional_msg: "calling Housekeeping.check_partition_interval!\n#{ExceptionHelper.memory_info_hash}")
      add_execption_to_job_warning(e)
      Database.close_db_connection                                              # Physically disconnect the DB connection of this thread, so that next request in this thread will re-open the connection again
    end
  end
end
