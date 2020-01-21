class SystemValidationJob < ApplicationJob
  queue_as :default

  def perform(*args)
    SystemValidationJob.set(wait: 60.seconds).perform_later unless Rails.env.test?  # Ensure next execution independent from following operations

    # Ensure that enough worker threads are operating for event transfer

  end
end
