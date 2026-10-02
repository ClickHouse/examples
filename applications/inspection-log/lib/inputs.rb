# frozen_string_literal: true
require 'date'
require 'digest'
require 'json'

module InspectionLog
  class InvalidInput < StandardError; end
  class Conflict < StandardError; end
  class CapacityReached < StandardError; end
  class ExportTooLarge < StandardError; end

  module Inputs
    CHECKS = %w[housing cable label].freeze
    OUTCOMES = %w[pass watch fail].freeze
    RESULTS = %w[ok issue].freeze
    MIN_DAY = Date.new(2000, 1, 1)
    MAX_DAY = Date.new(2100, 12, 31)
    FORM_FIELDS = %w[authenticity_token request_id asset_id inspected_on outcome housing cable label note].freeze
    FILTER_FIELDS = %w[asset_id from to outcome].freeze

    module_function

    def text(value, maximum)
      raise InvalidInput, 'Expected text' unless value.is_a?(String)
      value = value.dup.force_encoding(Encoding::UTF_8)
      raise InvalidInput, 'Text is not valid UTF-8' unless value.valid_encoding?
      raise InvalidInput, 'Text is too long' if value.length > maximum
      raise InvalidInput, 'Text contains unsupported controls' if value.match?(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]/)
      value
    end

    def integer(value, maximum)
      raise InvalidInput, 'Expected a bounded positive integer' unless value.is_a?(String) && value.match?(/\A[1-9][0-9]{0,2}\z/)
      parsed = Integer(value, 10)
      raise InvalidInput, 'Identifier is outside the supported range' if parsed > maximum
      parsed
    end

    def uuid(value)
      raise InvalidInput, 'A canonical request UUID is required' unless value.is_a?(String) && value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      value.downcase
    end

    def day(value)
      raise InvalidInput, 'Use a YYYY-MM-DD calendar day' unless value.is_a?(String) && value.match?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/)
      parsed = Date.iso8601(value)
      raise InvalidInput, 'Supported calendar days are 2000–2100' unless (MIN_DAY..MAX_DAY).cover?(parsed)
      parsed
    rescue Date::Error
      raise InvalidInput, 'Invalid calendar day'
    end

    def fields(input, allowed)
      raise InvalidInput, 'Unknown form field' unless input.is_a?(Hash) && (input.keys - allowed).empty?
      input.each_value { |value| text(value, 2_000) }
    end

    def form(input)
      fields(input, FORM_FIELDS)
      request_id = uuid(input['request_id'])
      asset_id = integer(input['asset_id'], 3)
      inspected_on = day(input['inspected_on'])
      outcome = input['outcome']
      raise InvalidInput, 'Choose an inspection outcome' unless OUTCOMES.include?(outcome)
      checklist = CHECKS.to_h do |name|
        result = input[name]
        raise InvalidInput, 'Complete every checklist result' unless RESULTS.include?(result)
        [name, result]
      end
      note = text(input.fetch('note', ''), 600).gsub(/\r\n?/, "\n")
      canonical = JSON.generate([asset_id, inspected_on.iso8601, outcome, CHECKS.map { |name| [name, checklist.fetch(name)] }, note])
      {request_id: request_id, asset_id: asset_id, inspected_on: inspected_on,
       outcome: outcome, checklist: checklist, note: note, digest: Digest::SHA256.hexdigest(canonical)}
    end

    def filters(input)
      fields(input, FILTER_FIELDS)
      asset_id = integer(input['asset_id'], 3)
      first = day(input['from'])
      last = day(input['to'])
      raise InvalidInput, 'Choose at most 31 calendar days in order' unless (0..30).cover?((last - first).to_i)
      outcome = input.fetch('outcome', '')
      raise InvalidInput, 'Unknown outcome filter' unless outcome.empty? || OUTCOMES.include?(outcome)
      {asset_id: asset_id, first: first, last: last, outcome: outcome}
    end
  end
end
