# This Job runs repeats itself permanent and runs once each hour
class HourlyJob < ApplicationJob
  queue_as :default
  CYCLE = 3600

  def perform(*args)
    HourlyJob.set(wait: CYCLE.seconds).perform_later unless Rails.env.test?  # Ensure next execution independent from following operations
    reset_job_warnings(CYCLE)

    # do housekeeping activities
    begin
      Database.set_application_info('HourlyJob/HousekeepingFinalErrors.do_housekeeping')
      HousekeepingFinalErrors.get_instance.do_housekeeping
    rescue Exception => e
      ExceptionHelper.log_exception(e, 'HourlyJob.perform', additional_msg: "calling HousekeepingFinalErrors.do_housekeeping!\n#{ExceptionHelper.memory_info_hash}")
      add_execption_to_job_warning(e)
    ensure
      Database.close_db_connection                                              # Physically disconnect the DB connection of this thread, so that next request in this thread will re-open the connection again
    end
  end
end
