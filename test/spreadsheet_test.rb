# -*- coding: utf-8 -*-
require "test_helper"

class SablonSpreadsheetTest < Sablon::TestCase
  def setup
    super
    @base_path = Pathname.new(File.expand_path("../", __FILE__))
    @template_path = @base_path + "fixtures/xlsx_report_template.xlsx"
    @output_path = @base_path + "sandbox/xlsx_report.xlsx"
    @sample_path = @base_path + "fixtures/xlsx_report_sample.xlsx"
    @context_path = @base_path + "fixtures/xlsx_report_context.json"
  end

  def test_generate_spreadsheet_from_template
    template = Sablon.template @template_path
    context = JSON.parse(File.read(@context_path))

    template.render_to_file @output_path, context

    assert_xlsx_equal @sample_path, @output_path
  end
end

class SablonSpreadsheetReferencesTest < Sablon::TestCase
  def setup
    super
    @base_path = Pathname.new(File.expand_path("../", __FILE__))
    @template_path = @base_path + "fixtures/xlsx_references_template.xlsx"
    @output_path = @base_path + "sandbox/xlsx_references.xlsx"
    @sample_path = @base_path + "fixtures/xlsx_references_sample.xlsx"
  end

  def test_generate_spreadsheet_from_template
    template = Sablon.template @template_path
    item = Struct.new(:name, :value)
    context = {
      customer: 'ACME',
      i: item.new('Head', 7),
      items: (1..4).map { |n| item.new("Item #{n}", n * 10) }
    }

    template.render_to_file @output_path, context

    assert_xlsx_equal @sample_path, @output_path
  end
end
