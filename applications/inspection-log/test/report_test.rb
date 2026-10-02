# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../lib/report'

class ReportTest < Minitest::Test
  def test_csv_quotes_multiline_text_and_mitigates_formula_prefixes
    ['=1+1', '+1', '-1', '@SUM(A1)', "\t=1+1", '  =1+1', "\n=1+1"].each do |text|
      assert_equal "'#{text}", InspectionLog::Report.spreadsheet_text(text)
    end
    note = "  =1+1,\"quoted\"\nsecond line"
    row = {id: 1, asset_name: 'Synthetic, bench', inspected_on: Date.new(2026,10,2),
           outcome: 'watch', checklist: {'housing'=>'ok','cable'=>'issue','label'=>'ok'},
           note: note, created_at: Time.iso8601('2026-10-02T09:30:00.123456Z')}
    parsed = CSV.parse(InspectionLog::Report.csv([row]), headers: true)
    assert_equal 1, parsed.length
    assert_equal 'Synthetic, bench', parsed[0]['asset']
    assert_equal "'#{note}", parsed[0]['note']
    assert_equal '2026-10-02', parsed[0]['inspected_on']
    assert_equal '2026-10-02T09:30:00.123456Z', parsed[0]['created_at_utc']
    assert_equal 'issue', parsed[0]['cable']
    assert_equal 'normal text', InspectionLog::Report.spreadsheet_text('normal text')
  end
end
