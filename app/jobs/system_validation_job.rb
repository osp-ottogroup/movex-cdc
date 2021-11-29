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
      ThreadHandling.get_instance.ensure_processing
    rescue Exception => e
      ExceptionHelper.log_exception(e, "SystemValidationJob.perform: calling ThreadHandling.ensure_processing! Proceeding with housekeeping.\n#{ExceptionHelper.memory_info_hash}")
      add_execption_to_job_warning(e)
    end

    # do housekeeping activities
    begin
      Database.set_application_info('SystemValidationJob/do_housekeeping')
      Housekeeping.get_instance.do_housekeeping
    rescue Exception => e
      ExceptionHelper.log_exception(e, "SystemValidationJob.perform: calling Housekeeping!\n#{ExceptionHelper.memory_info_hash}")
      add_execption_to_job_warning(e)
    end
  end
end
