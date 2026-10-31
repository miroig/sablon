require "test_helper"
require "support/xlsx_builder"

class SpreadsheetDOMTest < Sablon::TestCase
  MAIN_NS = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'.freeze

  def workbook(inner)
    xml = %(<workbook xmlns="#{MAIN_NS}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">#{inner}</workbook>)
    Sablon::DOM::Workbook.new(Nokogiri::XML(xml))
  end

  def test_sheets
    wb = workbook('<sheets><sheet name="Data" sheetId="1" r:id="rId1"/><sheet name="My Sheet" sheetId="2" r:id="rId5"/></sheets>')
    assert_equal [%w[Data rId1], ['My Sheet', 'rId5']], wb.sheets.map { |sheet| [sheet.name, sheet.rid] }
  end

  def test_date1904
    assert !workbook('<workbookPr/>').date1904?
    assert workbook('<workbookPr date1904="1"/>').date1904?
    assert workbook('<workbookPr date1904="true"/>').date1904?
  end

  def test_full_calc_on_load_updates_existing_calc_pr
    wb = workbook('<sheets/><calcPr calcId="191029"/>')
    wb.full_calc_on_load!
    assert_equal '<calcPr calcId="191029" fullCalcOnLoad="1"/>', wb.instance_variable_get(:@root).at_xpath('./*[last()]').to_xml
  end

  def test_full_calc_on_load_inserts_calc_pr_in_schema_order
    wb = workbook('<workbookPr/><sheets/><definedNames/><extLst/>')
    wb.full_calc_on_load!
    names = wb.instance_variable_get(:@root).element_children.map(&:name)
    assert_equal %w[workbookPr sheets definedNames calcPr extLst], names
  end

  def test_shared_strings
    xml = %(<sst xmlns="#{MAIN_NS}" count="5" uniqueCount="2"><si><t>a</t></si><si><r><t>b</t></r></si></sst>)
    doc = Nokogiri::XML(xml)
    strings = Sablon::DOM::SharedStrings.new(doc)
    assert_equal 'a', strings[0].text
    assert_equal 'b', strings[1].text
    assert_nil strings[2]
    strings.adjust_count(-2)
    assert_equal '3', doc.root['count']
  end

  def test_model_exposes_spreadsheet_package
    builder = XlsxBuilder.new.add_sheet('Data', '').add_sheet('Other', '')
    builder.shared_strings = ['x']
    Zip::File.open(builder.write(sandbox('dom_test.xlsx'))) do |zip|
      model = Sablon::DOM::Model.new(zip)
      package = model.spreadsheet
      assert_same package, model.spreadsheet
      assert_equal({ 'xl/worksheets/sheet1.xml' => 'Data', 'xl/worksheets/sheet2.xml' => 'Other' }, package.worksheets)
      assert_equal 'x', package.shared_strings[0].text
      assert_equal [['rId1', 'xl/worksheets/sheet1.xml']], package.related('xl/workbook.xml', 'worksheet').first(1)
    end
  end

  private

  def sandbox(name)
    File.expand_path("../../sandbox/#{name}", __FILE__)
  end
end
