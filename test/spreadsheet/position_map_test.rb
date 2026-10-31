require "test_helper"

class PositionMapTest < Sablon::TestCase
  PositionMap = Sablon::Spreadsheet::PositionMap
  Token = PositionMap::Token
  Entry = PositionMap::Entry
  Axis = PositionMap::Axis

  # Template rows 3 to 5 contain a loop: row 3 and 5 hold the control fields
  # and row 4 is repeated twice. Rows after the loop move up by one row.
  def setup
    super
    @first = Token.new('loop', 1, 0)
    @second = Token.new('loop', 2, 1)
    entries = { 4 => [Entry.new(3, [@first], nil), Entry.new(4, [@second], nil)] }
    @map = PositionMap.new(Axis.new(3, 5, -1, entries))
  end

  def map(text, context = nil, mode = :formula)
    ref = Sablon::Spreadsheet::Formula.references(text).first
    @map.map_reference(ref, context, mode)
  end

  def test_positions_outside_of_the_region
    assert_equal [2, 1], @map.first(2, 1)
    assert_equal [6, 2], @map.first(7, 2)
    assert_equal 'B2', map('B2')
    assert_equal '$B$6', map('$B$7')
  end

  def test_single_cells_from_outside_cover_all_copies
    assert_equal 'C3:C4', map('C4')
    assert_equal '$C$3:$C$4', map('$C$4')
    assert_equal '#REF!', map('C3')
    assert_equal '#REF!', map('C5')
  end

  def test_references_within_the_same_iteration
    assert_equal 'C4', map('C4', [[@second], []])
    assert_equal 'C3', map('C4', [[@first], []])
    # anchored references from within the loop use the first copy
    assert_equal 'C$3', map('C$4', [[@second], []])
  end

  def test_ranges_cover_all_copies
    assert_equal 'C3:C4', map('C4:C4')
    assert_equal 'C3:C4', map('C3:C5')
    assert_equal 'C2:D6', map('C2:D7')
    assert_equal 'C4:C4', map('C4:C4', [[@second], []])
    assert_equal '#REF!', map('C5:C5')
  end

  def test_anchored_ranges_grow_with_each_iteration
    assert_equal '$C$3:C3', map('$C$4:C4', [[@first], []])
    assert_equal '$C$3:C4', map('$C$4:C4', [[@second], []])
  end

  def test_area_mode_expands_single_cells
    assert_equal 'C3:C4', map('C4', nil, :area)
    assert_equal 'C2', map('C2', nil, :area)
  end

  def test_first_mode_uses_the_first_copy
    assert_equal 'C3', map('C4', nil, :first)
    assert_equal 'C3:C4', map('C4:C4', nil, :first)
  end

  def test_row_ranges
    assert_equal '3:4', map('4:4')
    assert_equal '$1:$6', map('$1:$7')
    assert_equal '#REF!', map('3:3')
  end

  def test_references_moved_beyond_the_sheet_limits
    # the loop in rows 3 to 5 adds two rows
    @map = PositionMap.new(Axis.new(3, 5, 2, 4 => [Entry.new(3, [], nil)]))
    assert_equal 'A1048575', map('A1048573')
    assert_equal '#REF!', map('A1048576')
    assert_equal '#REF!', map('$A$1048575')
    assert_equal '#REF!', map('A10:B1048576')
    assert_equal '#REF!', map('10:1048576')
    assert_equal '1048575:1048575', map('1048573:1048573')
  end

  def test_single_entries_are_matched_against_the_iteration
    # the outer loop repeats rows 1 to 6 twice, the inner loop only
    # generates a copy of row 4 in the first iteration
    outer1 = Token.new('outer', 1, 0)
    outer2 = Token.new('outer', 2, 1)
    inner = Token.new('inner', 3, 0)
    @map = PositionMap.new(Axis.new(1, 6, -2, 4 => [Entry.new(2, [outer1, inner], nil)]))
    assert_equal 'B2', map('B4', [[outer1], []])
    assert_equal '#REF!', map('B4', [[outer2], []])
    assert_equal '#REF!', map('B4:B4', [[outer2], []])
    assert_equal 'B2', map('B4')
  end

  def test_column_ranges_are_not_changed
    assert_nil map('A:C')
  end

  def test_point_collapses_removed_rows
    assert_equal [3, 2], @map.point(3, 2)
    assert_equal [5, 2], @map.point(5, 2)
    assert_equal [6, 2], @map.point(7, 2)
  end

  def test_identity
    map = PositionMap.identity
    assert map.identity?
    assert_equal [10, 3], map.first(10, 3)
    assert !@map.identity?
  end

  def test_axis_changes
    unchanged = Axis.new(1, 2, 0, 1 => [Entry.new(1, [], nil)], 2 => [Entry.new(2, [], nil)])
    assert !unchanged.changed?
    assert !unchanged.changes?(1, 5)
    moved = Axis.new(1, 2, 0, 1 => [Entry.new(1, [], nil)], 2 => [Entry.new(3, [], nil)])
    assert moved.changed?
    assert moved.changes?(2, 2)
    assert !moved.changes?(4, 5)
    shifted = Axis.new(1, 2, 1, 1 => [Entry.new(1, [], nil)], 2 => [Entry.new(2, [], nil), Entry.new(3, [], nil)])
    assert shifted.changes?(4, 5)
    assert !shifted.changes?(0, 0)
  end

  def test_column_loops
    # template row 2: B2 and D2 hold the control fields of a column loop
    # repeating C2 three times.
    copies = (0..2).map { |i| Token.new('cols', 10 + i, i) }
    columns = Axis.new(2, 4, 0, 3 => copies.each_with_index.map { |token, i| Entry.new(2 + i, [token], nil) })
    map = PositionMap.new(Axis.new(2, 2, 0, 2 => [Entry.new(2, [], columns)]))
    assert_equal [2, 2], map.first(2, 3)
    assert_equal [2, 5], map.first(2, 5)
    assert_equal [2, 2, 2, 4], map.extent(2, 3, 2, 3)
    assert_nil map.first(2, 2)
    # parallel loops: the iteration with the same index is used
    other = Token.new('other', 99, 1)
    assert_equal [2, 3], map.first(2, 3, [], [other])
    assert map.column_changes?(2, 2, 3, 3)
    assert map.column_changes?(1, 2, 6, 7) == false
  end
end
