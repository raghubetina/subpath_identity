# frozen_string_literal: true

require "test_helper"
require "rack/mock_request"

class RequireWorkerOriginTest < Minitest::Test
  SECRET = "worker-secret-value"

  def setup
    SubpathIdentity.configure do |c|
      c.worker_shared_secret_env_var = "TEST_WORKER_SHARED_SECRET"
      c.worker_origin_exempt_paths = ["/internal/me"]
    end
    ENV["TEST_WORKER_SHARED_SECRET"] = SECRET
    @downstream_called = false
    @app = SubpathIdentity::RequireWorkerOrigin.new(->(_env) {
      @downstream_called = true
      [200, {}, ["ok"]]
    })
  end

  def teardown
    SubpathIdentity.reset_config!
    ENV.delete("TEST_WORKER_SHARED_SECRET")
  end

  def call(path, headers: {})
    env = Rack::MockRequest.env_for(path, headers.transform_keys { |k| "HTTP_#{k.upcase.tr("-", "_")}" })
    @app.call(env)
  end

  def test_rejects_a_request_with_no_worker_secret_header
    status, = call("/")

    assert_equal 403, status
    refute @downstream_called
  end

  def test_rejects_a_request_with_the_wrong_worker_secret_header
    status, = call("/", headers: {"X-Worker-Secret" => "wrong"})

    assert_equal 403, status
    refute @downstream_called
  end

  def test_allows_a_request_with_the_correct_worker_secret_header
    status, = call("/", headers: {"X-Worker-Secret" => SECRET})

    assert_equal 200, status
    assert @downstream_called
  end

  def test_the_health_check_is_exempt_even_with_no_header
    status, = call("/up")

    assert_equal 200, status
    assert @downstream_called
  end

  def test_app_configured_exempt_paths_are_exempt_even_with_no_header
    status, = call("/internal/me")

    assert_equal 200, status
    assert @downstream_called
  end

  def test_an_unrelated_path_is_still_protected
    status, = call("/some-other-path")

    assert_equal 403, status
    refute @downstream_called
  end
end
