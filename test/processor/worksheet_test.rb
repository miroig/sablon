# -*- coding: utf-8 -*-
require "test_helper"
require "support/xlsx_builder"

class ProcessorWorksheetTest < Sablon::TestCase
  include XlsxCells
  include XlsxRendering

  def render(rows, context, options = {})
    builder = XlsxBuilder.new
    builder.date1904 = options.fetch(:date1904, false)
    builder.shared_strings = options.fetch(:shared_strings, [])
    builder.add_sheet('Data', rows.join, after: options.fetch(:after, ''))
    render_xlsx(builder, context, 'worksheet_processor')
  end

  def test_insertion
    rows = [row(1, text('A1', 'Hello {{=name}}!'), shared('B1', 0), text('C1', '{{=person.address.city}}'))]
    context = { name: 'World', title: 'Report', person: { address: { city: 'Zürich' } } }
    out = render(rows, context, shared_strings: ['{{=title}}'])
    assert_equal({ 'A1' => 'Hello World!', 'B1' => 'Report', 'C1' => 'Zürich' }, cell_values(out))
  end

  def test_native_values_keep_the_cell_style
    rows = [row(1, text('A1', '{{=date}}', 1), text('B1', '{{=time}}', 1), text('C1', '{{=amount}}', 3),
                text('D1', '{{=flag}}'), text('E1', '{{=nothing}}', 2), text('F1', '{{=forced}}'),
                text('G1', '{{=count}} items'))]
    context = { date: Date.new(2024, 2, 29), time: Time.new(2024, 2, 29, 18, 0, 0), amount: 1234.5,
                flag: true, nothing: nil, forced: Sablon.content(:string, 42), count: 3 }
    out = render(rows, context)
    assert_equal({ 'A1' => '45351', 'B1' => '45351.75', 'C1' => '1234.5', 'D1' => true,
                   'E1' => nil, 'F1' => '42', 'G1' => '3 items' }, cell_values(out))
    xml = sheet_xml(out)
    assert_includes xml, '<c r="A1" s="1">'
    assert_includes xml, '<c r="C1" s="3">'
    assert_includes xml, '<c r="E1" s="2"/>'
  end

  def test_dates_use_the_date_system_of_the_workbook
    out = render([row(1, text('A1', '{{=date}}', 1))], { date: Date.new(2024, 2, 29) }, date1904: true)
    assert_equal({ 'A1' => '43889' }, cell_values(out))
  end

  def test_row_loop
    rows = [row(1, text('A1', 'Name'), text('B1', 'Price')),
            row(2, text('A2', '{{items:each(item)}}')),
            row(3, text('A3', '{{=item.name}}'), text('B3', '{{=item.price}}'), formula('C3', 'B3*2')),
            row(5, text('A5', 'gap above'), formula('C5', 'C3+C2')),
            row(6, text('A6', '{{items:endEach}}')),
            row(7, text('A7', 'Total'), formula('B7', 'SUM(B3:B3)')),
            row(9, text('A9', 'end'), formula('B9', 'B7'))]
    out = render(rows, items: [{ name: 'A', price: 1 }, { name: 'B', price: 2 }])
    expected = { 'A1' => 'Name', 'B1' => 'Price',
                 'A2' => 'A', 'B2' => '1', 'C2' => '=B2*2', 'A4' => 'gap above', 'C4' => '=C2+#REF!',
                 'A5' => 'B', 'B5' => '2', 'C5' => '=B5*2', 'A7' => 'gap above', 'C7' => '=C5+#REF!',
                 'A8' => 'Total', 'B8' => '=SUM(B2:B5)', 'A10' => 'end', 'B10' => '=B8' }
    assert_equal expected, cell_values(out)
    assert_includes sheet_xml(out), '<dimension ref="A1:C10"/>'
  end

  def test_empty_loop
    rows = [row(1, text('A1', '{{items:each(item)}}')),
            row(2, text('A2', '{{=item}}')),
            row(3, text('A3', '{{items:endEach}}')),
            row(4, text('A4', 'after'), formula('B4', 'COUNTA(A1:A3)'))]
    out = render(rows, items: [])
    assert_equal({ 'A1' => 'after', 'B1' => '=COUNTA(#REF!)' }, cell_values(out))
  end

  def test_nested_loops
    rows = [row(1, text('A1', '{{groups:each(group)}}')),
            row(2, text('A2', '{{=group.name}}'), formula('B2', 'SUBTOTAL(9,B4:B4)'), formula('C2', 'MAX(B4)')),
            row(3, text('A3', '{{group.items:each(item)}}')),
            row(4, text('A4', '{{=item}}'), text('B4', '{{=item}}'), formula('C4', 'B4/B2')),
            row(5, text('A5', '{{group.items:endEach}}')),
            row(6, text('A6', '{{groups:endEach}}')),
            row(7, text('A7', 'Total'), formula('B7', 'SUBTOTAL(9,B4:B4)'))]
    out = render(rows, groups: [{ name: 'G1', items: [1, 2] }, { name: 'G2', items: [3] }])
    expected = { 'A1' => 'G1', 'B1' => '=SUBTOTAL(9,B2:B3)', 'C1' => '=MAX(B2:B3)',
                 'A2' => '1', 'B2' => '1', 'C2' => '=B2/B1', 'A3' => '2', 'B3' => '2', 'C3' => '=B3/B1',
                 'A4' => 'G2', 'B4' => '=SUBTOTAL(9,B5:B5)', 'C4' => '=MAX(B5)',
                 'A5' => '3', 'B5' => '3', 'C5' => '=B5/B4',
                 'A6' => 'Total', 'B6' => '=SUBTOTAL(9,B2:B5)' }
    assert_equal expected, cell_values(out)
  end

  def test_conditionals
    rows = [row(1, text('A1', '{{status:if(empty?)}}')),
            row(2, text('A2', 'empty')),
            row(3, text('A3', '{{status:elsif(nil?)}}')),
            row(4, text('A4', 'nil')),
            row(5, text('A5', '{{status:else}}')),
            row(6, text('A6', 'status: {{=status}}')),
            row(7, text('A7', '{{status:endIf}}')),
            row(8, text('A8', '{{show:if}}'), text('B8', 'removed with the control row')),
            row(9, text('A9', 'shown')),
            row(10, text('A10', '{{show:endIf}}'))]
    assert_equal({ 'A1' => 'status: ok' }, cell_values(render(rows, status: 'ok', show: false)))
    assert_equal({ 'A1' => 'empty', 'A2' => 'shown' }, cell_values(render(rows, status: '', show: [1])))
  end

  def test_column_loop
    rows = [row(1, text('A1', 'Year'), text('B1', '{{years:each(year)}}'), text('C1', '{{=year}}', 2),
                text('D1', '{{years:endEach}}'), text('E1', 'Total')),
            row(2, text('A2', 'Value'), text('B2', '{{years:each(year)}}'), text('C2', '{{=year}}'),
                text('D2', '{{years:endEach}}'), formula('E2', 'SUM(C2:C2)'), formula('F2', 'MAX(C2)'))]
    out = render(rows, years: [2023, 2024, 2025])
    expected = { 'A1' => 'Year', 'B1' => '2023', 'C1' => '2024', 'D1' => '2025', 'E1' => 'Total',
                 'A2' => 'Value', 'B2' => '2023', 'C2' => '2024', 'D2' => '2025',
                 'E2' => '=SUM(B2:D2)', 'F2' => '=MAX(B2:D2)' }
    assert_equal expected, cell_values(out)
    assert_includes sheet_xml(out), '<c r="D1" s="2">'
    #
    out = render(rows, years: [])
    assert_equal({ 'A1' => 'Year', 'B1' => 'Total', 'A2' => 'Value', 'B2' => '=SUM(#REF!)', 'C2' => '=MAX(#REF!)' },
                 cell_values(out))
  end

  def test_cross_tab
    rows = [row(1, text('A1', 'Product'), text('B1', '{{months:each(m)}}'), text('C1', '{{=m}}'),
                text('D1', '{{months:endEach}}'), text('E1', 'Total')),
            row(2, text('A2', '{{products:each(p)}}')),
            row(3, text('A3', '{{=p.name}}'), text('B3', '{{p.sales:each(s)}}'), text('C3', '{{=s}}'),
                text('D3', '{{p.sales:endEach}}'), formula('E3', 'SUM(C3:C3)')),
            row(4, text('A4', '{{products:endEach}}')),
            row(5, text('A5', 'Total'), text('B5', '{{months:each(m)}}'), formula('C5', 'SUM(C3:C3)'),
                text('D5', '{{months:endEach}}'), formula('E5', 'SUM(E3:E3)'))]
    context = { months: %w[Jan Feb], products: [{ name: 'A', sales: [1, 2] }, { name: 'B', sales: [3, 4] }] }
    expected = { 'A1' => 'Product', 'B1' => 'Jan', 'C1' => 'Feb', 'D1' => 'Total',
                 'A2' => 'A', 'B2' => '1', 'C2' => '2', 'D2' => '=SUM(B2:C2)',
                 'A3' => 'B', 'B3' => '3', 'C3' => '4', 'D3' => '=SUM(B3:C3)',
                 'A4' => 'Total', 'B4' => '=SUM(B2:B3)', 'C4' => '=SUM(C2:C3)', 'D4' => '=SUM(D2:D3)' }
    assert_equal expected, cell_values(render(rows, context))
  end

  def test_blocks_within_a_single_cell_are_not_supported
    rows = [row(1, text('A1', '{{items:each(i)}}{{=i}}{{items:endEach}}'))]
    e = assert_raises(Sablon::TemplateError) { render(rows, items: [1]) }
    assert_match(/need to be in different cells/, e.message)
  end

  def test_missing_end_field
    rows = [row(1, text('A1', '{{items:each(i)}}')), row(2, text('A2', '{{=i}}'))]
    e = assert_raises(Sablon::TemplateError) { render(rows, items: [1]) }
    assert_equal 'Could not find end field for «items:each(i)». Was looking for «items:endEach»', e.message
  end

  def test_unknown_placeholders_are_kept
    rows = [row(1, text('A1', '{{unknown}} {{=known}}'))]
    assert_equal({ 'A1' => '{{unknown}} yes' }, cell_values(render(rows, known: 'yes')))
  end

  def test_custom_field_handlers
    klass = Sablon::Processor::Worksheet
    klass.register_field_handler :comment, Sablon::Processor::Document::CommentHandler.new
    rows = [row(1, text('A1', '{{comment}}')), row(2, text('A2', 'note')), row(3, text('A3', '{{endComment}}')),
            row(4, text('A4', 'kept'))]
    assert_equal({ 'A1' => 'kept' }, cell_values(render(rows, {})))
  ensure
    klass.remove_field_handler :comment
  end

  def test_implicit_row_and_cell_numbers
    rows = ['<row><c t="inlineStr"><is><t>{{items:each(i)}}</t></is></c></row>',
            '<row><c t="inlineStr"><is><t>{{=i}}</t></is></c><c><v>5</v></c></row>',
            '<row><c t="inlineStr"><is><t>{{items:endEach}}</t></is></c></row>',
            '<row><c t="inlineStr"><is><t>end</t></is></c></row>']
    assert_equal({ 'A1' => 'x', 'B1' => '5', 'A2' => 'y', 'B2' => '5', 'A3' => 'end' },
                 cell_values(render(rows, items: %w[x y])))
  end

  def test_row_limit
    rows = [row(1_048_574, text('A1048574', '{{items:each(i)}}')),
            row(1_048_575, text('A1048575', '{{=i}}')),
            row(1_048_576, text('A1048576', '{{items:endEach}}'))]
    e = assert_raises(Sablon::ContextError) { render(rows, items: [1, 2, 3, 4]) }
    assert_equal 'The rendered worksheet exceeds the maximum number of rows (1048576)', e.message
  end

  def test_annotations_are_removed
    rows = [%(<row r="1" spans="1:4">#{text('A1', 'Name')}#{text('B1', '{{l:each(i)}}')}#{text('C1', '{{=i}}')}#{text('D1', '{{l:endEach}}')}</row>),
            row(2, text('A2', '{{l:each(i)}}')), row(4, text('A4', '{{=i}}')), row(5, text('A5', '{{l:endEach}}'))]
    xml = sheet_xml(render(rows, l: [1, 2]))
    assert_equal [], xml.scan(/sablon-[a-z]+/)
    assert_includes xml, '<row r="1">'
  end
end
