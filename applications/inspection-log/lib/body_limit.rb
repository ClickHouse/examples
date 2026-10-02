# frozen_string_literal: true
require 'stringio'
require 'uri'

module InspectionLog
  class BodyLimit
    MAX_BYTES = 32_768
    def initialize(app) = @app = app
    def call(env)
      return @app.call(env) unless env['REQUEST_METHOD'] == 'POST'
      return rejection(415, 'Use a URL-encoded form') unless env['CONTENT_TYPE'].to_s.split(';').first == 'application/x-www-form-urlencoded'
      bytes = env['rack.input'].read(MAX_BYTES + 1)
      return rejection(413, 'Form is too large') if bytes.bytesize > MAX_BYTES
      # Empty separators follow Rack's ordinary form parsing and are ignored.
      keys = bytes.split('&').reject(&:empty?).map do |pair|
        key = URI.decode_www_form_component(pair.split('=', 2).first, Encoding::UTF_8)
        raise ArgumentError unless key.valid_encoding?
        key
      end
      return rejection(400, 'Duplicate form fields are not accepted') unless keys.uniq.length == keys.length
      env['rack.input'] = StringIO.new(bytes)
      @app.call(env)
    rescue ArgumentError
      rejection(400, 'Malformed form encoding')
    end
    private
    def rejection(status, message) = [status, {'content-type' => 'text/plain; charset=utf-8'}, [message]]
  end
end
