# frozen_string_literal: true

require "test_helper"

class OriginSecretTest < Minitest::Test
  SECRET = "worker-secret-value"

  def test_valid_is_true_when_the_provided_value_matches_the_expected_secret
    assert SubpathIdentity::OriginSecret.valid?(SECRET, SECRET)
  end

  def test_valid_is_false_for_a_mismatched_value
    refute SubpathIdentity::OriginSecret.valid?(SECRET, "wrong-value")
  end

  def test_valid_is_false_for_a_nil_or_blank_provided_value
    refute SubpathIdentity::OriginSecret.valid?(SECRET, nil)
    refute SubpathIdentity::OriginSecret.valid?(SECRET, "")
  end

  def test_valid_is_false_for_a_value_of_a_different_length_than_the_secret
    refute SubpathIdentity::OriginSecret.valid?(SECRET, SECRET + "-extra")
    refute SubpathIdentity::OriginSecret.valid?(SECRET, SECRET[0..-2])
  end
end
