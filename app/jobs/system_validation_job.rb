# This Job runs repeats itself permanent
class SystemValidationJob < ApplicationJob
  queue_as :default
  CYCLE = 60

  def perform(*args)
    SystemValidationJob.set(wait: CYCLE.seconds).perform_later unless Rails.env.test?  # Ensure next execution independent from following operations
    reset_job_warnings(CYCLE)

    # Ensure that enough worker threads are operating for event transfer
    begin
      Database.set_application_info('SystemValidationJob/ensure_processing')
      Heartbeat.record_heartbeat
      ThreadHandling.get_instance.ensure_processing
      Heartbeat.check_for_concurrent_instance                                   # If exception is raised here, it means that another server instance is running with same hostname and IP address
    rescue Exception => e
      ExceptionHelper.log_exception(e, 'SystemValidationJob.perform', additional_msg: "calling ThreadHandling.ensure_processing! Proceeding with housekeeping.\n#{ExceptionHelper.memory_info_hash}")
      add_execption_to_job_warning(e)
      Database.close_db_connection                                              # Physically disconnect the DB connection of this thread, so that next request in this thread will re-open the connection again
    end

    # do housekeeping activities
    begin
      Database.set_application_info('SystemValidationJob/do_housekeeping')
      Housekeeping.get_instance.do_housekeeping
    rescue Exception => e
      ExceptionHelper.log_exception(e, 'SystemValidationJob.perform', additional_msg: "calling Housekeeping!\n#{ExceptionHelper.memory_info_hash}")
      add_execption_to_job_warning(e)
      Database.close_db_connection                                              # Physically disconnect the DB connection of this thread, so that next request in this thread will re-open the connection again
    end
  end
end
