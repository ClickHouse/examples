# frozen_string_literal: true
require 'csv'
require 'time'
require_relative 'inputs'

module InspectionLog
  module Report
    module_function

    def spreadsheet_text(value)
      # Apostrophe changes exported text. This is a bounded mitigation, not a universal importer guarantee.
      value.match?(/\A(?:[[:space:]]*[=+\-@]|[\t\r\n])/) ? "'#{value}" : value
    end

    def csv(rows)
      CSV.generate(row_sep: "\r\n") do |output|
        output << %w[inspection_id asset inspected_on outcome housing cable label note created_at_utc]
        rows.each do |row|
          output << [row.fetch(:id), spreadsheet_text(row.fetch(:asset_name)), row.fetch(:inspected_on).iso8601,
            row.fetch(:outcome), *Inputs::CHECKS.map { |name| row.fetch(:checklist).fetch(name) },
            spreadsheet_text(row.fetch(:note)), row.fetch(:created_at).getutc.iso8601(6)]
        end
      end
    end
  end
end
