require 'rake'

class InitializationJob < ApplicationJob
  queue_as :default

  def perform(*args)
    puts "Initialization at startup"
    ensure_admin_existence

    Rails.logger.info "Start db:migrate to ensure up to date data structures"
    Trixx::Application.load_tasks
    Rake::Task['db:migrate'].invoke
    Rails.logger.info "Finished db:migrate"

    # After initialization regular operation can start
    SystemValidationJob.set(wait: 1.seconds).perform_later unless Rails.env.test? # Job is tested separately
  end

  # ensure that user admin exists
  def ensure_admin_existence
    admin = User.find_by_email 'admin'
    unless admin
      # create admin user if not yet exists
      ActiveRecord::Base.transaction do
        user = User.new(email: 'admin', first_name: 'Admin', last_name: 'as Supervisor', db_user: Trixx::Application.config.trixx_db_user, yn_admin: 'Y')
        user.save!
      end
    end
  end
end
