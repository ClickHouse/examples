# frozen_string_literal: true
require 'minitest/autorun'
require 'rack/mock'
require_relative '../lib/body_limit'

class BodyLimitTest < Minitest::Test
  def middleware
    InspectionLog::BodyLimit.new(->(env) { [200, {'content-type'=>'text/plain'}, [env['rack.input'].read]] })
  end
  def test_duplicate_and_oversized_forms_fail_before_downstream_parser
    client = Rack::MockRequest.new(middleware)
    assert_equal 400, client.post('/', 'CONTENT_TYPE'=>'application/x-www-form-urlencoded', input:'note=one&%6Eote=two').status
    assert_equal 413, client.post('/', 'CONTENT_TYPE'=>'application/x-www-form-urlencoded', input:'x' * 32_769).status
    assert_equal 200, client.post('/', 'CONTENT_TYPE'=>'application/x-www-form-urlencoded', input:'a=1&&b=2').status
    assert_equal 415, client.post('/', 'CONTENT_TYPE'=>'application/json', input:'{}').status
    assert_equal 400, client.post('/', 'CONTENT_TYPE'=>'application/x-www-form-urlencoded', input:'bad%=1').status
    response=client.post('/', 'CONTENT_TYPE'=>'application/x-www-form-urlencoded', input:'note=one%26two')
    assert_equal 200, response.status
    assert_equal 'note=one%26two', response.body
  end
end
