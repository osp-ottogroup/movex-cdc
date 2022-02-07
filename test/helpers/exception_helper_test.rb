require 'test_helper'

class ExceptionHelperTest < ActiveSupport::TestCase

  test "limited_wait_for_mutex" do
    mutex = Mutex.new

    start_time = Time.now
    ExceptionHelper.limited_wait_for_mutex(mutex: mutex)
    assert Time.now - start_time < 1, log_on_failure('ExceptionHelper.limited_wait_for_mutex should return immediately if mutex is not locked')

    mutex.lock

    start_time = Time.now
    ExceptionHelper.limited_wait_for_mutex(mutex: mutex, max_wait_time_secs: 1)
    assert Time.now - start_time > 1, log_on_failure('ExceptionHelper.limited_wait_for_mutex should have waited if mutex is locked')

    assert_raise(Exception, 'ExceptionHelper.limited_wait_for_mutex should have raised exception if mutex is locked') do
      ExceptionHelper.limited_wait_for_mutex(mutex: mutex, raise_exception: true, max_wait_time_secs: 1)
    end
  end
end
