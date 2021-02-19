require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test "create user" do
    assert_difference('User.count') do
      User.new(email: 'Hans.Dampf@web.de', first_name: 'Hans', last_name: 'Dampf', db_user: Trixx::Application.config.trixx_db_victim_user).save!
    end

    # Second user
    assert_difference('User.count') do
      User.new(email: 'Hans.Dampf2@web.de', first_name: 'Hans', last_name: 'Dampf', db_user: Trixx::Application.config.trixx_db_victim_user).save!
    end

    assert_raise(Exception, 'Duplicate should raise unique index violation') { User.new(email: 'Hans.Dampf@web.de', first_name: 'Hans', last_name: 'Dampf', db_user: Trixx::Application.config.trixx_db_victim_user).save! }
  end

  test "select user" do
    users = User.all
    assert(users.count > 0, 'Should return at least one user')
  end

  test "destroy user" do
    ActivityLog.new(user_id: users(:one).id, action: 'At least one activity_logs record to prevent user from delete by foreign key').save!
    users(:one).destroy!
    assert_equal 'Y', User.find(users(:one).id).yn_account_locked, 'Account should be locked instead of delete after destroy if foreign keys prevents this'

    # Remove objects that may cause foreign key error
    ActivityLog.all.each do |al|
      al.destroy!
    end

    assert_difference('User.count', -1, 'User should be physically deleted now') do
      users(:one).destroy!
    end
  end

  test "should have deployable schemas" do
    # using fixtures user(:one), schema_rights(:one) and schema(:one)
    ds = users(:one).deployable_schemas
    assert(ds.count == 1, 'Should have one deployable schema')
    assert(ds.first.name == schemas(:one).name, 'Should be correct schema name')
  end

  test "should not have deployable schemas" do
    SchemaRight.new(user_id: users(:two).id, schema_id: schemas(:one).id, info: 'Info', yn_deployment_granted: 'N').save!
    ds = users(:two).deployable_schemas
    assert(ds.count == 0, 'Should have no deployable schemas')
  end

  test "should be able to deploy schemas" do
    # using fixtures user(:one), schema_rights(:one) and schema(:one)
    can_deploy = users(:one).can_deploy_schemas?
    assert(can_deploy)
  end

  test "should not be able to deploy schemas" do
    SchemaRight.new(user_id: users(:two).id, schema_id: schemas(:one).id, info: 'Info', yn_deployment_granted: 'N').save!
    can_deploy = users(:two).can_deploy_schemas?
    assert(can_deploy == false)
  end

end
