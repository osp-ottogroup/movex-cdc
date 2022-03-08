require 'thread_handling'

at_exit do
  Rails.logger.warn('initializers/at_exit'){ "Process exit catched by , shutting down transfer workers now" }
  ThreadHandling.get_instance.shutdown_processing
  Rails.logger.warn('initializers/at_exit'){ "MOVEX Change Data Capture: application gracefully shutted down now" }
end