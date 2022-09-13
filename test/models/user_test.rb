require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test "create user" do
    run_with_current_user do
      assert_difference('User.count') do
        User.new(email: 'Hans.Dampf@web.de', first_name: 'Hans', last_name: 'Dampf', db_user: MovexCdc::Application.config.db_victim_user).save!
      end

      # Second user
      assert_difference('User.count') do
        User.new(email: 'Hans.Dampf2@web.de', first_name: 'Hans', last_name: 'Dampf', db_user: MovexCdc::Application.config.db_victim_user).save!
      end

      assert_raise(Exception, 'Duplicate should raise unique index violation') { User.new(email: 'Hans.Dampf@web.de', first_name: 'Hans', last_name: 'Dampf', db_user: MovexCdc::Application.config.db_victim_user).save! }

      User.where(email: 'Hans.Dampf@web.de').first.destroy                        # cleanup user table
      User.where(email: 'Hans.Dampf2@web.de').first.destroy                       # cleanup user table
    end
  end

  test "select user" do
    users = User.all
    assert users.count > 0, log_on_failure('Should return at least one user')
  end

  test "destroy user" do
    user_to_delete = User.new(email: 'hans.dampf@hugo.de', db_user: MovexCdc::Application.config.db_user, first_name: 'hans', last_name: 'dampf', yn_account_locked: 'N')
    run_with_current_user { user_to_delete.save! }

    ActivityLog.new(user_id: user_to_delete.id, action: 'At least one activity_logs record to prevent user from delete by foreign key').save!
    run_with_current_user { user_to_delete.destroy! }
    assert_equal 'Y', User.find(user_to_delete.id).yn_account_locked, log_on_failure('Account should be locked instead of delete after destroy if foreign keys prevents this')

    # Remove objects that may cause foreign key error
    ActivityLog.where(user_id: user_to_delete.id).each do |al|
      al.destroy!
    end

    assert_difference('User.count', -1, 'User should be physically deleted now') do
      run_with_current_user { User.find(user_to_delete.id).destroy! }
    end
  end

  test "should have deployable schemas" do
    # remove possibly existing record
    run_with_current_user do
      SchemaRight.where(user_id: sandro_user.id, schema_id: user_schema.id).each {|sr| sr.destroy!}

      sr = SchemaRight.new(user_id: sandro_user.id, schema_id: user_schema.id, info: 'Info', yn_deployment_granted: 'Y')
      sr.save!
      ds = sandro_user.deployable_schemas
      assert ds.count == 1, log_on_failure('Should have one deployable schema')
      assert ds.first.name == user_schema.name, log_on_failure('Should be correct schema name')
      sr.destroy!
    end
  end

  test "should not have deployable schemas" do
    # remove possibly existing record
    SchemaRight.where(user_id: sandro_user.id, schema_id: user_schema.id).each {|sr| sr.destroy!}

    sr = SchemaRight.new(user_id: sandro_user.id, schema_id: user_schema.id, info: 'Info', yn_deployment_granted: 'N')
    run_with_current_user { sr.save! }
    ds = sandro_user.deployable_schemas
    assert ds.count == 0, log_on_failure('Should have no deployable schemas')
    run_with_current_user { sr.destroy! }
  end

  test "should be able to deploy schemas" do
    can_deploy = peter_user.can_deploy_schemas?
    assert(can_deploy)
  end

  test "should not be able to deploy schemas" do
    run_with_current_user do
      # remove possibly existing record
      SchemaRight.where(user_id: sandro_user.id, schema_id: user_schema.id).each {|sr| sr.destroy!}

      sr = SchemaRight.new(user_id: sandro_user.id, schema_id: user_schema.id, info: 'Info', yn_deployment_granted: 'N')
      sr.save!
      can_deploy = sandro_user.can_deploy_schemas?
      assert(can_deploy == false)
      sr.destroy!
    end
  end

  test "increment failed logons" do
    user = User.find(sandro_user.id)
    original_count = user.failed_logons
    user.increment_failed_logons
    user = User.find(sandro_user.id)                                            # Reload from DB
    assert_equal original_count+1, user.failed_logons, 'Failed logons should be incremented by 1'
    user.reset_failed_logons # Restore original state
  end

  test "lock account" do
    User.find(sandro_user.id).lock_account
    reloaded_user = User.find(sandro_user.id)
    assert_equal 'Y', reloaded_user.yn_account_locked, 'User should be locked now'
    # Restore original state
    reloaded_user.yn_account_locked = 'N'
    reloaded_user.save!
  end

  test "check_for_system_init_completed" do
    assert_nothing_raised do
      User.check_for_system_init_completed
    end
  end
end
