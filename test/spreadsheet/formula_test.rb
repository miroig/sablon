# -*- coding: utf-8 -*-
require "test_helper"

class FormulaTest < Sablon::TestCase
  Formula = Sablon::Spreadsheet::Formula

  def refs(text)
    Formula.references(text).map { |ref| [ref.scope, ref.sheet, text[ref.start...ref.stop]] }
  end

  def test_finds_cells_and_ranges
    assert_equal [[:local, nil, 'A1'], [:local, nil, '$B$2:C$3']], refs('A1+SUM($B$2:C$3)')
  end

  def test_finds_whole_rows_and_columns
    assert_equal [[:local, nil, 'A:C'], [:local, nil, '$2:$4']], refs('SUM(A:C)+SUM($2:$4)')
  end

  def test_ignores_functions_names_numbers_and_strings
    formula = 'LOG10(A1)+ATAN2(1,2)+1E10+2.5e-3+"B2 C3"&Q1Sales+TRUE+_xlfn.XLOOKUP(D4,E:E,F:F)'
    assert_equal ['A1', 'D4', 'E:E', 'F:F'], refs(formula).map(&:last)
  end

  def test_ignores_out_of_range_names
    assert_equal [], refs('XFE1+A0+ABCD1')
  end

  def test_qualified_references
    formula = %q(Sheet1!A1+'My Sheet'!B2:C3+'It''s'!D4+Übersicht!E5)
    assert_equal [[:sheet, 'Sheet1', 'A1'], [:sheet, 'My Sheet', 'B2:C3'],
                  [:sheet, "It's", 'D4'], [:sheet, 'Übersicht', 'E5']], refs(formula)
  end

  def test_external_and_3d_references
    formula = %q([1]Sheet1!A1+'[2]Other Sheet'!B2+Sheet1:Sheet3!C3+'Jan:Mar'!D4+E5)
    assert_equal [[:external, 'Sheet1', 'A1'], [:external, '[2]Other Sheet', 'B2'],
                  [:external, 'Sheet1', 'C3'], [:external, 'Jan:Mar', 'D4'],
                  [:local, nil, 'E5']], refs(formula)
  end

  def test_ignores_structured_references_and_errors
    formula = %q(SUM(Table1[[#This Row],[Col'[1']]])+[@A1]+#REF!+#N/A+G7)
    assert_equal ['G7'], refs(formula).map(&:last)
  end

  def test_rewrite
    result = Formula.rewrite('A1+Sheet2!B2*"A1"') do |ref|
      ref.scope == :local ? 'Z9' : nil
    end
    assert_equal 'Z9+Sheet2!B2*"A1"', result
  end

  def test_rewrite_with_multibyte_characters
    result = Formula.rewrite('"äöü"&A1&Übersicht!B2') { |ref| ref.to_s.downcase }
    assert_equal '"äöü"&a1&Übersicht!b2', result
  end

  def test_translate
    assert_equal 'B3+$A$1+C$1+$A3', Formula.translate('A2+$A$1+B$1+$A2', 1, 1)
    assert_equal 'SUM(B2:B10)', Formula.translate('SUM(A1:A9)', 1, 1)
    assert_equal 'SUM(4:5)+SUM(B:C)', Formula.translate('SUM(3:4)+SUM(A:B)', 1, 1)
    assert_equal 'Sheet1!#REF!+1', Formula.translate('Sheet1!A2+1', -2, 0)
  end

  def test_reference_to_s
    ref = Formula.references('$A1:B$2').first
    assert_equal :range, ref.kind
    assert_equal '$A1:B$2', ref.to_s
  end

  def test_rewrite_sqref
    result = Formula.rewrite_sqref('A1 B2:C3 D4') do |ref|
      ref.to_s == 'D4' ? Formula::REF_ERROR : ref.to_s.downcase
    end
    assert_equal 'a1 b2:c3', result
  end
end
