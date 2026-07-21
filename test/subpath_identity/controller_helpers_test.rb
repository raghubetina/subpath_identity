# frozen_string_literal: true

require "test_helper"

class ControllerHelpersTest < Minitest::Test
  class FakeController < ActionController::Base
    include SubpathIdentity::ControllerHelpers

    def index
      head :ok
    end
  end

  def setup
    SubpathIdentity.configure do |c|
      c.allowed_claims = %i[user_id dark_mode]
      c.claim_defaults = {user_id: nil, dark_mode: false}
      c.cookie_name = :_shared_identity
    end
    @previous_secret = ENV["SHARED_SESSION_SECRET"]
    ENV["SHARED_SESSION_SECRET"] = "a-test-secret-long-enough-to-pass-the-floor"
  end

  def teardown
    SubpathIdentity.reset_config!
    ENV["SHARED_SESSION_SECRET"] = @previous_secret
  end

  def build_controller
    controller = FakeController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.response = ActionDispatch::TestResponse.new
    controller
  end

  def test_clear_shared_identity_deletes_the_cookie_and_resets_the_in_request_identity
    controller = build_controller
    # cookies is private on ActionController::Base — reach it with send.
    controller.send(:cookies)[:_shared_identity] = "some-encoded-token"
    # Stand in for what load_shared_identity would have memoized on a
    # real request — a signed-in identity.
    controller.instance_variable_set(:@current_shared_identity, {user_id: 42, dark_mode: true})
    assert controller.signed_in?

    controller.clear_shared_identity

    refute controller.signed_in?, "should read as signed out for the rest of this request"
    assert_equal SubpathIdentity.config.claim_defaults, controller.current_shared_identity
    assert_nil controller.send(:cookies)[:_shared_identity], "the cookie should be deleted"
  end

  # Regression for the renewable-lease bug: an ordinary claim write (a
  # dark-mode toggle) must carry the identity's ORIGINAL absolute
  # deadline into the new cookie, not stamp a fresh now + cookie_ttl —
  # otherwise any cookie holder can keep a replayed or closed-account
  # identity alive forever by toggling a preference before expiry.
  def test_an_ordinary_write_preserves_the_identitys_absolute_deadline
    original_deadline = Time.now + 300
    controller = build_controller
    controller.instance_variable_set(:@current_shared_identity, {user_id: 42, dark_mode: false})
    controller.instance_variable_set(:@shared_identity_expires_at, original_deadline)

    controller.write_shared_identity(dark_mode: true)

    decoded, expires_at = SubpathIdentity::SharedIdentity.decode_with_expiry(
      ENV["SHARED_SESSION_SECRET"], controller.send(:cookies)[:_shared_identity]
    )
    assert_equal 42, decoded[:user_id]
    assert_equal true, decoded[:dark_mode]
    assert_equal original_deadline.to_i, expires_at.to_i,
      "the rewrite must not extend the identity's life"
  end

  def test_renew_lifetime_true_mints_a_fresh_absolute_deadline
    stale_deadline = Time.now + 300
    controller = build_controller
    controller.instance_variable_set(:@current_shared_identity, {user_id: 42, dark_mode: false})
    controller.instance_variable_set(:@shared_identity_expires_at, stale_deadline)

    controller.write_shared_identity(renew_lifetime: true, user_id: 42)

    _decoded, expires_at = SubpathIdentity::SharedIdentity.decode_with_expiry(
      ENV["SHARED_SESSION_SECRET"], controller.send(:cookies)[:_shared_identity]
    )
    assert_in_delta (Time.now + SubpathIdentity.config.cookie_ttl).to_i, expires_at.to_i, 5
    assert expires_at > stale_deadline, "a real auth event mints a new window"
  end

  def test_shared_identity_expires_at_reflects_an_anonymous_preferences_cookie
    # An anonymous visitor toggling a preference is signed out (no
    # user_id) but still gets a cookie with a deadline — the reader
    # tracks the cookie, not signed_in?.
    controller = build_controller
    controller.instance_variable_set(:@current_shared_identity, SubpathIdentity.config.claim_defaults)
    controller.instance_variable_set(:@shared_identity_expires_at, nil)

    controller.write_shared_identity(dark_mode: true)

    refute controller.signed_in?, "still anonymous"
    refute_nil controller.shared_identity_expires_at, "but the cookie has a deadline"
    assert_in_delta (Time.now + SubpathIdentity.config.cookie_ttl).to_i, controller.shared_identity_expires_at.to_i, 5
  end

  def test_a_write_with_no_signed_in_identity_mints_a_fresh_deadline
    controller = build_controller
    controller.instance_variable_set(
      :@current_shared_identity,
      SubpathIdentity.config.claim_defaults
    )

    controller.write_shared_identity(dark_mode: true)

    _decoded, expires_at = SubpathIdentity::SharedIdentity.decode_with_expiry(
      ENV["SHARED_SESSION_SECRET"], controller.send(:cookies)[:_shared_identity]
    )
    assert_in_delta (Time.now + SubpathIdentity.config.cookie_ttl).to_i, expires_at.to_i, 5
  end

  # Regression for the same-request write clobber: write_shared_identity
  # used to leave @current_shared_identity untouched, so a second write
  # in the same request merged over the identity that ARRIVED on the
  # request and its cookie silently discarded the first write's claims
  # (a relying party's cache-key reissue in a before_action, wiped out
  # by the action's own dark-mode toggle). Each write must see the one
  # before it, and the preserved deadline must survive both.
  def test_two_writes_in_one_request_compose_instead_of_last_write_winning
    original_deadline = Time.now + 300
    controller = build_controller
    controller.instance_variable_set(:@current_shared_identity, {user_id: 42, dark_mode: false})
    controller.instance_variable_set(:@shared_identity_expires_at, original_deadline)

    controller.write_shared_identity(user_id: 43)
    controller.write_shared_identity(dark_mode: true)

    assert_equal 43, controller.current_shared_identity[:user_id],
      "the in-request identity must reflect the first write"

    decoded, expires_at = SubpathIdentity::SharedIdentity.decode_with_expiry(
      ENV["SHARED_SESSION_SECRET"], controller.send(:cookies)[:_shared_identity]
    )
    assert_equal 43, decoded[:user_id], "the final cookie must carry BOTH writes' claims"
    assert_equal true, decoded[:dark_mode]
    assert_equal original_deadline.to_i, expires_at.to_i,
      "the absolute deadline must survive consecutive writes"
  end
end
