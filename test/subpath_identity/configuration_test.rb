# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def teardown
    SubpathIdentity.reset_config!
    ENV.delete("CUSTOM_SHARED_SECRET")
  end

  def test_defaults
    config = SubpathIdentity::Configuration.new

    assert_equal [], config.allowed_claims
    assert_equal({}, config.claim_defaults)
    assert_equal 24 * 60 * 60, config.cookie_ttl
    assert_equal "SHARED_SESSION_SECRET", config.shared_session_secret_env_var
    assert_equal "WORKER_SHARED_SECRET", config.worker_shared_secret_env_var
    assert_equal [], config.worker_origin_exempt_paths
    assert_equal :_shared_identity, config.cookie_name
  end

  def test_configure_yields_the_global_config_object
    SubpathIdentity.configure do |c|
      c.allowed_claims = %i[user_id]
    end

    assert_equal %i[user_id], SubpathIdentity.config.allowed_claims
  end

  def test_shared_session_secret_reads_from_the_configured_env_var_name
    SubpathIdentity.configure { |c| c.shared_session_secret_env_var = "CUSTOM_SHARED_SECRET" }
    ENV["CUSTOM_SHARED_SECRET"] = "the-actual-secret"

    assert_equal "the-actual-secret", SubpathIdentity.config.shared_session_secret
  end

  def test_shared_session_secret_raises_when_the_env_var_is_missing
    SubpathIdentity.configure { |c| c.shared_session_secret_env_var = "CUSTOM_SHARED_SECRET" }

    assert_raises(KeyError) { SubpathIdentity.config.shared_session_secret }
  end
end
