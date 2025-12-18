require 'test_helper'

class HeartbeatTest < ActiveSupport::TestCase

  test "current_ip_address" do
    address = Heartbeat.current_ip_address
    assert_not_nil address, "IP address should not be nil"
  end

  test "record_heartbeat" do
    assert_nothing_raised do
      Heartbeat.record_heartbeat
    end
    heartbeat = Heartbeat.find_by(hostname: Socket.gethostname, ip_address: Heartbeat.current_ip_address)
    assert_not_nil heartbeat, "Heartbeat record should exist"
    assert_not_nil heartbeat.heartbeat_ts, "Heartbeat timestamp should not be nil"
  end

  test "check_for_concurrent_instance" do
    Heartbeat.record_heartbeat
    assert_nothing_raised do
      Heartbeat.check_for_concurrent_instance
    end

    # Simulate another instance by creating a heartbeat with different hostname or IP
    other_hostname = "other_host"
    other_ip = "10.10.10.10"

    existing_heartbeat = Heartbeat.find_by(hostname: other_hostname, ip_address: other_ip)
    if existing_heartbeat.nil?
      Heartbeat.create!(hostname: other_hostname, ip_address: other_ip, heartbeat_ts: Time.current)
    else
      existing_heartbeat.update!(heartbeat_ts: Time.current)
    end

    Heartbeat.check_for_concurrent_instance

    last_line = nil
    File.foreach(Rails.root.join('log', "test.log")) do |line|
      last_line = line
    end
    assert last_line["This might be a false positive"], "Last line of log '#{last_line}' should contain 'This might be a false positive'"
    Heartbeat.where(hostname: other_hostname, ip_address: other_ip).delete_all  # Remove the simulated record
  end

end
