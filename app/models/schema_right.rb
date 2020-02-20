class SchemaRight < ApplicationRecord
  belongs_to :user
  belongs_to :schema

  # user = User
  # user_request_params = [ { :info, schema: { :name }  } ]
  def self.process_user_request(user, user_request_params)
    SchemaRight.where(user_id: user.id).each do |sr|                            # iterate over existing schema_rights of user
      sr.destroy unless user_request_params.map{|r| r[:schema][:name]}.include? sr.schema.name  # remove schema_rights from user that are no more in list
    end

    user_request_params.each do |p|
      schema =  Schema.find_by_name(p[:schema][:name])
      if schema.nil?                                                            # create schema if not already exists
        schema = Schema.new(name: p[:schema][:name])
        schema.save!
      end
      schema_right = SchemaRight.find_by_user_id_and_schema_id(user.id, schema.id)
      if schema_right
        schema_right.update!(info: p[:info])                                    # update existing schema_right
      else                                                                      # create schema_right if not yet exists
        schema_right = SchemaRight.new(user_id: user.id, schema_id: schema.id, info: p[:info])
        schema_right.save!
      end
    end

  end

end
