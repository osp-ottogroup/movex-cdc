# This Job runs repeats itself permanent
class SystemValidationJob < ApplicationJob
  queue_as :default

  def perform(*args)
    SystemValidationJob.set(wait: 60.seconds).perform_later unless Rails.env.test?  # Ensure next execution independent from following operations
    reset_job_warnings

    # Ensure that enough worker threads are operating for event transfer
    begin
      Database.set_application_info('SystemValidationJob/ensure_processing')
      ThreadHandling.get_instance.ensure_processing
    rescue Exception => e
      ExceptionHelper.log_exception(e, "SystemValidationJob.perform: calling ThreadHandling.ensure_processing! Proceeding with housekeeping.")
      add_execption_to_job_warning(e)
    end

    # do housekeeping activities
    begin
      Database.set_application_info('SystemValidationJob/do_housekeeping')
      Housekeeping.get_instance.do_housekeeping
    rescue Exception => e
      ExceptionHelper.log_exception(e, "SystemValidationJob.perform: calling Housekeeping!")
      add_execption_to_job_warning(e)
    end
  end
end
