class InitializationJob < ApplicationJob
  queue_as :default

  def perform(*args)
    puts "Initialization at startup"
    ensure_admin_existence
  end

  # ensure that user admin exists
  def ensure_admin_existence
    admin = User.find_by_email 'admin'
    unless admin
      # create admin user if not yet exists
      ActiveRecord::Base.transaction do
        user = User.new(email: 'admin', first_name: 'Admin', last_name: 'as Supervisor', db_user: Trixx::Application.config.trixx_db_user)
        user.save!
      end
    end
  end
end
