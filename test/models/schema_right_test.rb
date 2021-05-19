require 'test_helper'

class SchemaRightTest < ActiveSupport::TestCase
  test "create schema_right" do
    new_sr = SchemaRight.where(user_id: sandro_user.id, schema_id: user_schema.id).first
    if new_sr.nil?                                                              # accept possible existence of SchemaRight?
      new_sr = SchemaRight.new(user_id: sandro_user.id, schema_id: user_schema.id, info: 'Info')
      new_sr.save!
    end
    assert_raise(Exception, 'Duplicate should raise unique index violation') { SchemaRight.new(user_id: sandro_user.id, schema_id: user_schema.id, info: 'Info').save! } # 1/1 from fixture
    new_sr.destroy!
  end

  test "select schema_right" do
    schema_rights = SchemaRight.all
    assert(schema_rights.count > 0, 'Should return at least one record')
  end

  test 'process_user_request' do
    admin = User.where(email: 'admin').first
    SchemaRight.process_user_request(admin, [{ info: 'LaLa', yn_deployment_granted: 'N', schema: { name: 'HUGO'}}])

    schema = Schema.where(name: 'HUGO').first
    assert_not_nil(schema, 'Should have created new schema record')

    schema_right = SchemaRight.where(user_id: admin.id, schema_id: schema.id).first
    assert_not_nil(schema_right, 'Should have created new schema_right record')

    assert_equal('LaLa', schema_right.info)
    SchemaRight.process_user_request(admin,
                                     [{ info:                   'HaHa',
                                        yn_deployment_granted:  'Y',
                                        lock_version:           schema_right.lock_version,
                                        schema:                 { name: 'HUGO'}
                                      }]
    )
    schema_right = SchemaRight.where(user_id: admin.id, schema_id: schema.id).first # reload object
    assert_equal('HaHa', schema_right.info, 'should have updated info')
    assert_equal('Y', schema_right.yn_deployment_granted, 'should have updated yn_deployment_granted')

    SchemaRight.process_user_request(admin, [])
    assert_nil(SchemaRight.where(user_id: admin.id, schema_id: schema.id).first, 'should remove schema right')

  end

  test 'process_user_request - update without lock version' do
    admin = User.where(email: 'admin').first
    SchemaRight.process_user_request(admin, [{ info: 'LaLa', yn_deployment_granted: 'N', schema: { name: 'HUGO'}}])

    schema = Schema.where(name: 'HUGO').first
    assert_not_nil(schema, 'Should have created new schema record')

    schema_right = SchemaRight.where(user_id: admin.id, schema_id: schema.id).first
    assert_not_nil(schema_right, 'Should have created new schema_right record')

    assert_equal('LaLa', schema_right.info)
    SchemaRight.process_user_request(admin,
                                     [{ info:                   'HaHa',
                                        yn_deployment_granted:  'Y',
                                        schema:                 { name: 'HUGO'}
                                      }]
    )
    schema_right = SchemaRight.where(user_id: admin.id, schema_id: schema.id).first # reload object
    assert_equal('HaHa', schema_right.info, 'should have updated info')
    assert_equal('Y', schema_right.yn_deployment_granted, 'should have updated yn_deployment_granted')

    SchemaRight.process_user_request(admin, [])
    assert_nil(SchemaRight.where(user_id: admin.id, schema_id: schema.id).first, 'should remove schema right')
  end

end
