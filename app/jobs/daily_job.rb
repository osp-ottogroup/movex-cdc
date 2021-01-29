# This Job runs repeats itself permanent and runs once each day
class DailyJob < ApplicationJob
  queue_as :default

  def perform(*args)
    DailyJob.set(wait: 86400.seconds).perform_later unless Rails.env.test?  # Ensure next execution independent from following operations

    # do housekeeping activities
    begin
      Database.set_application_info('DailyJob/CompressStatistics.do_compress')
      CompressStatistics.get_instance.do_compress
    rescue Exception => e
      ExceptionHelper.log_exception(e, "HourlyJob.perform: calling CompressStatistics.do_compress!")
    end
  end
end
