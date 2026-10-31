require "test_helper"

class CellValueTest < Sablon::TestCase
  CellValue = Sablon::Spreadsheet::CellValue

  def xml(node)
    node.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)
  end

  def test_native_numbers
    assert_equal ['n', '42'], CellValue.native(42)
    assert_equal ['n', '-1.5'], CellValue.native(-1.5)
    assert_equal ['n', '1.0e+20'], CellValue.native(1e20)
    assert_equal ['n', '0.25'], CellValue.native(Rational(1, 4))
    # BigDecimal is a bundled gem since Ruby 3.4, only test it when loaded
    assert_equal ['n', '12.34'], CellValue.native(BigDecimal('12.34')) if defined?(BigDecimal)
    assert_nil CellValue.native(Float::NAN)
    assert_nil CellValue.native(Float::INFINITY)
    assert_nil CellValue.native(Complex(1, 2))
  end

  def test_native_booleans
    assert_equal ['b', '1'], CellValue.native(true)
    assert_equal ['b', '0'], CellValue.native(false)
  end

  def test_native_ignores_other_values
    assert_nil CellValue.native('42')
    assert_nil CellValue.native(nil)
    assert_nil CellValue.native(:symbol)
  end

  def test_date_serials_1900
    assert_equal ['n', '1'], CellValue.native(Date.new(1900, 1, 1))
    assert_equal ['n', '59'], CellValue.native(Date.new(1900, 2, 28))
    assert_equal ['n', '61'], CellValue.native(Date.new(1900, 3, 1))
    assert_equal ['n', '45351'], CellValue.native(Date.new(2024, 2, 29))
    assert_nil CellValue.native(Date.new(1899, 12, 31))
  end

  def test_date_serials_1904
    assert_equal ['n', '0'], CellValue.native(Date.new(1904, 1, 1), true)
    assert_equal ['n', '43889'], CellValue.native(Date.new(2024, 2, 29), true)
    assert_nil CellValue.native(Date.new(1903, 12, 31), true)
  end

  def test_times_use_the_fraction_of_the_day
    assert_equal ['n', '45351.5'], CellValue.native(Time.new(2024, 2, 29, 12, 0, 0, '+05:00'))
    assert_equal ['n', '45351.75'], CellValue.native(DateTime.new(2024, 2, 29, 18, 0, 0))
    serial = CellValue.native(Time.utc(2024, 2, 29, 0, 0, 1)).last.to_f
    assert_in_delta 45351 + 1.0 / 86_400, serial, 1e-9
  end

  def test_escape_text
    assert_equal 'a_x005F_x0041_b', CellValue.escape_text('a_x0041_b')
    assert_equal "tab\tline\nbell_x0007_", CellValue.escape_text("tab\tline\nbell\a")
    assert_equal '_x', CellValue.escape_text('_x')
  end

  def test_write_native_keeps_style_and_order
    doc = Nokogiri::XML('<c xmlns="x" r="A1" s="3" t="inlineStr"><is><t>a</t></is><extLst/></c>')
    CellValue.write_native(doc.root, 'b', '1')
    assert_equal '<c xmlns="x" r="A1" s="3" t="b"><v>1</v><extLst/></c>', xml(doc.root)
  end

  def test_clear
    doc = Nokogiri::XML('<c xmlns="x" r="A1" s="3" t="inlineStr"><is><t>a</t></is></c>')
    CellValue.clear(doc.root)
    assert_equal '<c xmlns="x" r="A1" s="3"/>', xml(doc.root)
  end
end
