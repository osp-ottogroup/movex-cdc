require 'thread_handling'

at_exit do
  Rails.logger.warn "Process exit catched by initializers/at_exit, shutting down transfer workers now"
  ThreadHandling.get_instance.shutdown_processing
  Rails.logger.warn "MOVEX Change Data Capture: application gracefully shutted down now"
end