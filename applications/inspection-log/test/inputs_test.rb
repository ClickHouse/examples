# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../lib/inputs'

class InputsTest < Minitest::Test
  def form
    {'request_id' => 'abcdef00-0000-0000-0000-000000000001', 'asset_id' => '1',
     'inspected_on' => '2026-10-02', 'outcome' => 'watch', 'housing' => 'ok',
     'cable' => 'issue', 'label' => 'ok', 'note' => 'Synthetic note'}
  end

  def test_exact_canonical_retry_and_calendar_date
    input = InspectionLog::Inputs.form(form)
    assert_instance_of Date, input[:inspected_on]
    assert_equal '2026-10-02', input[:inspected_on].iso8601
    assert_equal input[:digest], InspectionLog::Inputs.form(form.merge('request_id' => form['request_id'].upcase))[:digest]
    assert_equal InspectionLog::Inputs.form(form.merge('note' => "line\r\nnext"))[:digest],
      InspectionLog::Inputs.form(form.merge('note' => "line\nnext"))[:digest]
    refute_equal input[:digest], InspectionLog::Inputs.form(form.merge('label' => 'issue'))[:digest]
    refute_equal input[:digest], InspectionLog::Inputs.form(form.merge('note' => 'Synthetic note '))[:digest]
  end

  def test_rejects_unknown_fields_membership_and_malformed_text
    [{ 'owner' => 'forged' }, { 'asset_id' => '01' }, { 'asset_id' => '9' },
     { 'asset_id' => '9' * 1000 }, { 'housing' => 'skip' }, { 'outcome' => 'unknown' },
     { 'request_id' => '1-1-1-1-1' }, { 'note' => "x\u0000" }, { 'note' => "x\u0085" },
     { 'note' => 'x' * 601 }, { 'note' => "\xff".b }, { 'note' => [] }].each do |changed|
      assert_raises(InspectionLog::InvalidInput) { InspectionLog::Inputs.form(form.merge(changed)) }
    end
    assert_raises(InspectionLog::InvalidInput) { InspectionLog::Inputs.uuid(nil) }
    assert_equal '', InspectionLog::Inputs.form(form.merge('note' => ''))[:note]
  end

  def test_date_and_range_boundaries
    ['2000-01-01', '2100-12-31'].each { |day| assert_equal day, InspectionLog::Inputs.day(day).iso8601 }
    ['1999-12-31', '2101-01-01', '2026-02-30', '2026-2-1'].each do |day|
      assert_raises(InspectionLog::InvalidInput) { InspectionLog::Inputs.day(day) }
    end
    filter = {'asset_id' => '1', 'from' => '2026-10-01', 'to' => '2026-10-31', 'outcome' => ''}
    assert_equal 30, (InspectionLog::Inputs.filters(filter)[:last] - InspectionLog::Inputs.filters(filter)[:first]).to_i
    assert_raises(InspectionLog::InvalidInput) { InspectionLog::Inputs.filters(filter.merge('to' => '2026-11-01')) }
    assert_raises(InspectionLog::InvalidInput) { InspectionLog::Inputs.filters(filter.merge('to' => '2026-09-30')) }
  end
end
