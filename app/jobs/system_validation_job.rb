# This Job runs repeats itself permanent
class SystemValidationJob < ApplicationJob
  queue_as :default

  def perform(*args)
    SystemValidationJob.set(wait: 60.seconds).perform_later unless Rails.env.test?  # Ensure next execution independent from following operations

    # Ensure that enough worker threads are operating for event transfer
    begin
      ThreadHandling.get_instance.ensure_processing
    rescue Exception => e
      ExceptionHelper.log_exception(e, "SystemValidationJob.perform: calling ThreadHandling.ensure_processing! Proceeding with housekeeping.")
    end

    # do housekeeping activities
    begin
      Housekeeping.get_instance.do_housekeeping
    rescue Exception => e
      ExceptionHelper.log_exception(e, "SystemValidationJob.perform: calling Housekeeping!")
    end
  end
end
