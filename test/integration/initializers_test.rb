require 'test_helper'

class InitializersTest < ActionDispatch::IntegrationTest
  def setup
    # Rails.application.initialize!  # Don't call it in setup!  See notes below
    # Instead call it in each test that requires it
  end

  def run_initializer(file_name)
    initializer_path = Rails.root.join("config", "initializers", "#{file_name}.rb") # Create the file path
    assert File.exist?(initializer_path), "Initializer file not found: #{initializer_path}"
    load initializer_path # Runs the code.
  end

  test "application initializer create_secrets" do
    assert_nothing_raised do
      assert Rails.application.initialized?

      new_secret_key_base = Random.rand(99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999).to_s
      run_initializer "create_secrets"                                          # run once to get DEFAULT_SECRET_KEY_BASE_FILE defined

      # Each scene represents a different environment or configuration
      # default: true if DEFAULT_SECRET_KEY_BASE_FILE should exist
      # secret_key_base_file: true, if using a path to file that should be used as SECRET_KEY_BASE_FILE
      # secret_key_base: true if used/set
      [
        { default: nil , secret_key_base_file: true, secret_key_base: true },
        { default: nil,  secret_key_base_file: nil,  secret_key_base: nil  },
        { default: nil , secret_key_base_file: true, secret_key_base: nil  },
        { default: nil , secret_key_base_file: nil,  secret_key_base: true },
        { default: true, secret_key_base_file: true, secret_key_base: true },
        { default: true, secret_key_base_file: nil,  secret_key_base: nil  },
        { default: true, secret_key_base_file: true, secret_key_base: nil  },
        { default: true, secret_key_base_file: nil,  secret_key_base: true },
      ].each do |scene|
        # defined starup scenario
        File.delete(DEFAULT_SECRET_KEY_BASE_FILE) if File.exist?(DEFAULT_SECRET_KEY_BASE_FILE) # remove the file DEFAULT_SECRET_KEY_BASE_FILE
        ENV.delete('SECRET_KEY_BASE_FILE')
        ENV.delete('SECRET_KEY_BASE')

        if scene[:default]
          File.write(DEFAULT_SECRET_KEY_BASE_FILE, new_secret_key_base)
        end

        if scene[:secret_key_base_file]
          env_file_path = Rails.root.join("tmp", "test_secret_key_base_file.txt")
          File.write(env_file_path, new_secret_key_base)
          ENV['SECRET_KEY_BASE_FILE'] = env_file_path.to_s
        end

        if scene[:secret_key_base]
          ENV['SECRET_KEY_BASE'] = new_secret_key_base.to_s
        end

        run_initializer "create_secrets"
      end
    end
  end


  test "database connection is properly configured" do
    # Rails.application.initialize! # Instead call it in each test that requires it
    # Verify the database connection is established
    assert ActiveRecord::Base.connection.active? # Or a more specific check
  end
end