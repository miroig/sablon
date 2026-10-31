require "test_helper"

class ExecutableTest < Sablon::TestCase
  def setup
    super
    @base_path = Pathname.new(File.expand_path("../", __FILE__))
    @output_path = @base_path + "sandbox/recipe.docx"
    @template_path = @base_path + "fixtures/recipe_template.docx"
    @sample_path = @base_path + "fixtures/recipe_sample.docx"
    @context_path = @base_path + "fixtures/recipe_context.json"
    @executable_path = @base_path + '../exe/sablon'
    @output_path.delete if @output_path.exist?
  end

  def test_generate_document_from_template_output_to_file
    `cat #{@context_path} | #{@executable_path} #{@template_path} #{@output_path}`

    assert_docx_equal @sample_path, @output_path
  end

  def test_generate_document_from_template_output_to_stdout
    `cat #{@context_path} | #{@executable_path} #{@template_path} > #{@output_path}`

    assert_docx_equal @sample_path, @output_path
  end

  def test_generate_spreadsheet_from_template
    output_path = @base_path + "sandbox/xlsx_report_executable.xlsx"
    template_path = @base_path + "fixtures/xlsx_report_template.xlsx"
    context_path = @base_path + "fixtures/xlsx_report_context.json"
    output_path.delete if output_path.exist?
    `cat #{context_path} | #{@executable_path} #{template_path} #{output_path}`

    assert_xlsx_equal @base_path + "fixtures/xlsx_report_sample.xlsx", output_path
  end
end
