at_exit do
  Rails.logger.info "Exit catched ======================"
  ThreadHandling.get_instance.shutdown_processing
end