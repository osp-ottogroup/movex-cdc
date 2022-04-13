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

  test "usr should be locked after x failed logons" do
    org_value = MovexCdc::Application.config.max_failed_logons_before_account_locked
    MovexCdc::Application.config.max_failed_logons_before_account_locked = 3
    sandro_user.increment_failed_logons
    sandro_user.increment_failed_logons
    sandro_user.increment_failed_logons
    assert_equal 'Y', User.find(sandro_user.id).yn_account_locked, 'Account should be locked now'
    User.find(sandro_user.id).reset_failed_logons                               # Restore original state
    MovexCdc::Application.config.max_failed_logons_before_account_locked = org_value # Restore original state
  end
end
