require "test_helper"

class CellReferenceTest < Sablon::TestCase
  CellReference = Sablon::Spreadsheet::CellReference

  def test_column_index_and_letters_round_trip
    { 'A' => 1, 'Z' => 26, 'AA' => 27, 'AZ' => 52, 'BA' => 53, 'XFD' => 16_384 }.each do |letters, index|
      assert_equal index, CellReference.column_index(letters)
      assert_equal letters, CellReference.column_letters(index)
    end
    assert_equal 28, CellReference.column_index('ab')
  end

  def test_parse
    assert_equal [12, 2], CellReference.parse('B12')
    assert_equal [1, 1], CellReference.parse('$A$1')
    assert_equal [1_048_576, 16_384], CellReference.parse('XFD1048576')
    assert_nil CellReference.parse('XFE1')
    assert_nil CellReference.parse('A1048577')
    assert_nil CellReference.parse('A0')
    assert_nil CellReference.parse('Sheet1')
    assert_nil CellReference.parse(nil)
  end

  def test_format
    assert_equal 'C7', CellReference.format(7, 3)
    assert_equal '$C$7', CellReference.format(7, 3, true, true)
    assert_equal 'C$7', CellReference.format(7, 3, true, false)
    assert_equal '$C7', CellReference.format(7, 3, false, true)
  end
end
