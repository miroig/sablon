# -*- coding: utf-8 -*-
require "test_helper"
require "support/xlsx_builder"

# Rows 3 to 5 of the "Data" sheet contain a loop repeating row 4. Rendered
# with 5 items the rows after the loop move down by two rows.
class ReferenceSyncTest < Sablon::TestCase
  include XlsxCells
  include XlsxRendering

  CT = 'application/vnd.openxmlformats-officedocument'.freeze

  def rows
    [row(1, text('A1', '{{=title}}')),
     row(2, text('A2', 'Name'), text('B2', 'Value')),
     row(3, text('A3', '{{items:each(item)}}')),
     row(4, text('A4', '{{=item.name}}'), text('B4', '{{=item.value}}')),
     row(5, text('A5', '{{items:endEach}}')),
     row(6, text('A6', 'Total'), formula('B6', 'SUM(B4:B4)')),
     row(8, text('A8', 'Below'), number('B8', 1))].join
  end

  def context(count = 5)
    { title: 'Title', items: (1..count).map { |i| { name: "Item #{i}", value: i } } }
  end

  def builder(after: '', rels: [])
    XlsxBuilder.new.add_sheet('Data', rows, after: after, rels: rels)
  end

  def test_formulas_of_other_sheets_and_defined_names
    b = builder
    b.add_sheet('My Sheet', row(1, formula('A1', "Data!B6+'DATA'!B4+'My Sheet'!A2+Other!B6"), formula('A2', 'SUM(Data!B3:B5)')))
    b.add_sheet('Other', row(6, number('B6', 1)))
    b.defined_names = [['Values', 'Data!$B$4:$B$4'], ['_xlnm.Print_Area', "'Data'!$A$1:$B$8", 0], ['Fixed', 'Other!$A$1']]
    out = render_xlsx(b, context)
    assert_equal({ 'A1' => "=Data!B8+'DATA'!B3:B7+'My Sheet'!A2+Other!B6", 'A2' => '=SUM(Data!B3:B7)' }, cell_values(out, 2))
    names = out['xl/workbook.xml'].xpath('//x:definedName', 'x' => XlsxBuilder::MAIN_NS).map(&:text)
    assert_equal ['Data!$B$3:$B$7', "'Data'!$A$1:$B$10", 'Other!$A$1'], names
  end

  def test_conditional_formatting_validation_and_filters
    ext = %(<extLst><ext uri="{78C0D931-6437-407d-A8EE-F0AAD7539E65}" xmlns:x14="http://schemas.microsoft.com/office/spreadsheetml/2009/9/main">) +
          %(<x14:conditionalFormattings><x14:conditionalFormatting xmlns:xm="http://schemas.microsoft.com/office/excel/2006/main">) +
          %(<x14:cfRule type="dataBar" id="{1}"><x14:dataBar><x14:cfvo type="formula"><xm:f>$B$8</xm:f></x14:cfvo></x14:dataBar></x14:cfRule>) +
          %(<xm:sqref>B4</xm:sqref></x14:conditionalFormatting></x14:conditionalFormattings></ext></extLst>)
    after = %(<autoFilter ref="A2:B5"><sortState ref="A3:B5"><sortCondition ref="B3:B5"/></sortState></autoFilter>) +
            %(<conditionalFormatting sqref="B4 B8"><cfRule type="expression" dxfId="0" priority="1"><formula>B4&gt;$B$8</formula></cfRule></conditionalFormatting>) +
            %(<conditionalFormatting sqref="A3"><cfRule type="expression" dxfId="0" priority="2"><formula>TRUE</formula></cfRule></conditionalFormatting>) +
            %(<dataValidations count="2"><dataValidation type="whole" sqref="B4"><formula1>0</formula1><formula2>$B$8</formula2></dataValidation>) +
            %(<dataValidation type="list" sqref="A5"><formula1>"a,b"</formula1></dataValidation></dataValidations>) + ext
    doc = render_xlsx(builder(after: after), context)['xl/worksheets/sheet1.xml']
    ns = { 'x' => XlsxBuilder::MAIN_NS, 'xm' => 'http://schemas.microsoft.com/office/excel/2006/main' }
    assert_equal ['A2:B7', 'A3:B7', 'B3:B7'], doc.xpath('//x:autoFilter/descendant-or-self::*[@ref]', ns).map { |n| n['ref'] }
    assert_equal ['B3:B7 B10'], doc.xpath('//x:conditionalFormatting', ns).map { |n| n['sqref'] }
    assert_equal ['B3>$B$10'], doc.xpath('//x:conditionalFormatting//x:formula', ns).map(&:text)
    validations = doc.at_xpath('//x:dataValidations', ns)
    assert_equal '1', validations['count']
    assert_equal [['B3:B7', '$B$10']], validations.xpath('x:dataValidation', ns).map { |n| [n['sqref'], n.at_xpath('x:formula2', ns).text] }
    assert_equal ['B3:B7'], doc.xpath('//xm:sqref', ns).map(&:text)
    assert_equal ['$B$10'], doc.xpath('//xm:f', ns).map(&:text)
  end

  def test_tables
    table = %(<table xmlns="#{XlsxBuilder::MAIN_NS}" id="1" name="Items" displayName="Items" ref="A2:B4" totalsRowShown="0">) +
            %(<autoFilter ref="A2:B4"/><tableColumns count="2"><tableColumn id="1" name="Name"/><tableColumn id="2" name="Value"/></tableColumns></table>)
    b = builder(after: '<tableParts count="1"><tablePart r:id="rId1"/></tableParts>', rels: [%w[table ../tables/table1.xml]])
    b.add_part('xl/tables/table1.xml', table, "#{CT}.spreadsheetml.table+xml")
    root = render_xlsx(b, context)['xl/tables/table1.xml'].root
    assert_equal 'A2:B7', root['ref']
    assert_equal 'A2:B7', root.at_xpath('x:autoFilter', 'x' => XlsxBuilder::MAIN_NS)['ref']
  end

  def test_table_column_names_follow_header_cells
    rows = row(1, text('A1', '{{=first}}'), text('B1', 'Fixed')) + row(2, number('A2', 1), number('B2', 2))
    table = %(<table xmlns="#{XlsxBuilder::MAIN_NS}" id="1" name="T" displayName="T" ref="A1:B2"><tableColumns count="2">) +
            %(<tableColumn id="1" name="{{=first}}"/><tableColumn id="2" name="Fixed"/></tableColumns></table>)
    b = XlsxBuilder.new.add_sheet('Data', rows, rels: [%w[table ../tables/table1.xml]])
    b.add_part('xl/tables/table1.xml', table, "#{CT}.spreadsheetml.table+xml")
    out = render_xlsx(b, first: 'Name')
    assert_equal %w[Name Fixed], out['xl/tables/table1.xml'].xpath('//x:tableColumn', 'x' => XlsxBuilder::MAIN_NS).map { |n| n['name'] }
  end

  def test_column_loops_within_tables_are_not_supported
    rows = row(1, text('A1', '{{cols:each(c)}}'), text('B1', '{{=c}}'), text('C1', '{{cols:endEach}}'))
    table = %(<table xmlns="#{XlsxBuilder::MAIN_NS}" id="1" name="T" displayName="T" ref="A1:C2"><tableColumns count="3"/></table>)
    b = XlsxBuilder.new.add_sheet('Data', rows, rels: [%w[table ../tables/table1.xml]])
    b.add_part('xl/tables/table1.xml', table, "#{CT}.spreadsheetml.table+xml")
    e = assert_raises(Sablon::TemplateError) { render_xlsx(b, cols: [1, 2]) }
    assert_equal "Column loops are not supported within the table 'T'", e.message
  end

  def test_drawings
    anchor = lambda do |type, from, to, attrs = ''|
      marker = ->(name, (col, row)) { "<xdr:#{name}><xdr:col>#{col}</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>#{row}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:#{name}>" }
      to_xml = to ? marker.call('to', to) : '<xdr:ext cx="1" cy="1"/>'
      "<xdr:#{type}#{attrs}>#{marker.call('from', from)}#{to_xml}<xdr:sp/><xdr:clientData/></xdr:#{type}>"
    end
    drawing = %(<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" ) +
              %(xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">) +
              anchor.call('twoCellAnchor', [3, 1], [6, 7]) +
              anchor.call('twoCellAnchor', [3, 3], [4, 3]) +
              anchor.call('twoCellAnchor', [3, 7], [4, 9], ' editAs="oneCell"') +
              anchor.call('twoCellAnchor', [3, 7], [4, 9], ' editAs="absolute"') +
              anchor.call('oneCellAnchor', [0, 4], nil) +
              %(<mc:AlternateContent><mc:Choice Requires="a14">#{anchor.call('twoCellAnchor', [0, 7], [1, 8])}</mc:Choice></mc:AlternateContent>) +
              '</xdr:wsDr>'
    b = builder(after: '<drawing r:id="rId1"/>', rels: [%w[drawing ../drawings/drawing1.xml]])
    b.add_part('xl/drawings/drawing1.xml', drawing, "#{CT}.drawing+xml")
    doc = render_xlsx(b, context)['xl/drawings/drawing1.xml']
    markers = doc.xpath('//*[local-name() = "from" or local-name() = "to"]').map do |node|
      [node.at_xpath('*[local-name() = "col"]').text.to_i, node.at_xpath('*[local-name() = "row"]').text.to_i]
    end
    # [col, row] pairs (0 based) of the from and to markers
    expected = [[3, 1], [6, 9], # spans the loop and grows
                [3, 2], [4, 2], # anchored to the repeated row, stays at the first copy
                [3, 9], [4, 11], # moves without changing the size
                [3, 7], [4, 9], # absolute
                [0, 7], # removed row collapses onto the row following the loop
                [0, 9], [1, 10]]
    assert_equal expected, markers
  end

  def test_charts
    chart = %(<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart><c:plotArea><c:barChart><c:ser>) +
            %(<c:tx><c:strRef><c:f>Data!$B$2</c:f><c:strCache><c:ptCount val="1"/></c:strCache></c:strRef></c:tx>) +
            %(<c:cat><c:strRef><c:f>Data!$A$4</c:f><c:strCache><c:ptCount val="1"/></c:strCache></c:strRef></c:cat>) +
            %(<c:val><c:numRef><c:f>Data!$B$4:$B$4</c:f><c:numCache><c:ptCount val="1"/></c:numCache></c:numRef></c:val>) +
            %(</c:ser></c:barChart></c:plotArea></c:chart></c:chartSpace>)
    b = builder
    b.add_part('xl/charts/chart1.xml', chart, "#{CT}.drawingml.chart+xml")
    doc = render_xlsx(b, context)['xl/charts/chart1.xml']
    assert_equal ['Data!$B$2', 'Data!$A$3:$A$7', 'Data!$B$3:$B$7'], doc.xpath('//*[local-name() = "f"]').map(&:text)
    assert_equal 0, doc.xpath('//*[local-name() = "strCache" or local-name() = "numCache"]').length
  end

  def test_comments
    comments = %(<comments xmlns="#{XlsxBuilder::MAIN_NS}"><authors><author>a</author></authors><commentList>) +
               %(<comment ref="A3" authorId="0"><text><t>control</t></text></comment>) +
               %(<comment ref="B4" authorId="0"><text><t>body</t></text></comment>) +
               %(<comment ref="B8" authorId="0"><text><t>below</t></text></comment></commentList></comments>)
    threaded = %(<ThreadedComments xmlns="http://schemas.microsoft.com/office/spreadsheetml/2018/threadedcomments">) +
               %(<threadedComment ref="A3" id="{1}"><text>control</text></threadedComment>) +
               %(<threadedComment ref="B8" id="{2}"><text>below</text></threadedComment></ThreadedComments>)
    note = ->(row, col) { %(<v:shape id="s#{row}" type="#_x0000_t202"><x:ClientData ObjectType="Note"><x:Anchor>#{col + 1}, 15, #{row}, 10, #{col + 3}, 15, #{row + 4}, 4</x:Anchor><x:Row>#{row}</x:Row><x:Column>#{col}</x:Column></x:ClientData></v:shape>) }
    vml = %(<xml xmlns:v="urn:schemas-microsoft-com:vml" xmlns:x="urn:schemas-microsoft-com:office:excel"><v:shapetype id="_x0000_t202"/>) +
          note.call(2, 0) + note.call(3, 1) + note.call(7, 1) + '</xml>'
    rels = [%w[comments ../comments1.xml], %w[vmlDrawing ../drawings/vmlDrawing1.vml],
            ['http://schemas.microsoft.com/office/2017/10/relationships/threadedComment', '../threadedComments/threadedComment1.xml']]
    b = builder(after: '<legacyDrawing r:id="rId2"/>', rels: rels)
    b.add_part('xl/comments1.xml', comments, "#{CT}.spreadsheetml.comments+xml")
    b.add_part('xl/drawings/vmlDrawing1.vml', vml)
    b.add_part('xl/threadedComments/threadedComment1.xml', threaded, 'application/vnd.ms-excel.threadedcomments+xml')
    out = render_xlsx(b, context)
    assert_equal %w[B3 B10], out['xl/comments1.xml'].xpath('//*[@ref]').map { |n| n['ref'] }
    assert_equal %w[B10], out['xl/threadedComments/threadedComment1.xml'].xpath('//*[@ref]').map { |n| n['ref'] }
    shapes = out['xl/drawings/vmlDrawing1.vml'].scan(%r{<x:Anchor>([^<]*)</x:Anchor><x:Row>(\d+)</x:Row><x:Column>(\d+)</x:Column>})
    assert_equal [['2, 15, 2, 10, 4, 15, 6, 4', '2', '1'], ['2, 15, 9, 10, 4, 15, 13, 4', '9', '1']], shapes
  end

  def test_workbook_preparation
    b = XlsxBuilder.new
    b.calc_chain = true
    b.shared_strings = ['Label', 'Unused {{=x}}']
    rows = row(1, shared('A1', 0), shared('B1', 1), '<c r="C1"><f t="shared" ref="C1:C3" si="0">A1&amp;B1</f><v>x</v></c>') +
           row(2, '<c r="C2"><f t="shared" si="0"/><v>x</v></c>') +
           row(3, '<c r="C3" t="str"><f t="shared" si="0"/><v>x</v></c>')
    b.add_sheet('Data', rows)
    b.add_sheet('Static', row(1, shared('A1', 0), '<c r="B1" t="str"><f>A1</f><v>Label</v></c>'))
    out = render_xlsx(b, x: 'y')
    assert_equal({ 'A1' => 'Label', 'B1' => 'Unused y', 'C1' => '=A1&B1', 'C2' => '=A2&B2', 'C3' => '=A3&B3' }, cell_values(out))
    assert_equal({ 'A1' => 'Label', 'B1' => '=A1' }, cell_values(out, 2))
    assert_includes sheet_xml(out, 2), '<c r="B1">'
    assert !out.key?('xl/calcChain.xml')
    assert !out['xl/_rels/workbook.xml.rels'].to_xml.include?('calcChain')
    assert !out['[Content_Types].xml'].to_xml.include?('calcChain')
    assert_equal '1', out['xl/workbook.xml'].at_xpath('//x:calcPr', 'x' => XlsxBuilder::MAIN_NS)['fullCalcOnLoad']
    assert_equal '1', out['xl/sharedStrings.xml'].root['count']
  end
end
