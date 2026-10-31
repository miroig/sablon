# -*- coding: utf-8 -*-
require "test_helper"

class WorksheetParserTest < Sablon::TestCase
  NS = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'.freeze

  def setup
    super
    @parser = Sablon::Parser::Worksheet.new
    @env = Sablon::Environment.new(nil)
  end

  def test_prepares_inline_strings
    doc = prepare(%(<row r="1"><c r="B1" s="2" t="inlineStr"><is><t>Hello {{=name}}!</t></is></c></row>))
    expected = %(<c r="B1" s="2" t="inlineStr" sablon-p="1"><is><r><t xml:space="preserve">Hello </t></r>) +
               %(<r sablon-f="=name" sablon-k="1:2:0"><t>{{=name}}</t></r><r><t>!</t></r></is></c>)
    assert_equal expected, xml(cell(doc))
  end

  def test_prepares_shared_strings
    strings = shared_strings('<si><t>{{=title}}</t></si>')
    doc = prepare(%(<row r="1"><c r="A1" t="s"><v>0</v></c></row>), strings)
    expected = %(<c r="A1" t="inlineStr" sablon-p="1" sablon-w="1"><is><r sablon-f="=title" sablon-k="1:1:0"><t>{{=title}}</t></r></is></c>)
    assert_equal expected, xml(cell(doc))
  end

  def test_placeholders_split_across_formatted_runs
    rows = %(<row r="1"><c r="A1" t="inlineStr"><is><r><rPr><b/></rPr><t xml:space="preserve">Name: {{=per</t></r>) +
           %(<r><rPr><i/></rPr><t xml:space="preserve">son.name}} end</t></r></is></c></row>)
    doc = prepare(rows)
    runs = cell(doc).xpath('x:is/x:r', 'x' => NS)
    assert_equal ['Name: ', '{{=person.name}}', ' end'], runs.map(&:text)
    assert_equal %w[b b i], runs.map { |run| run.at_xpath('x:rPr/*', 'x' => NS).name }
    assert_equal [nil, '=person.name', nil], runs.map { |run| run['sablon-f'] }
  end

  def test_whitespace_inside_of_placeholders
    doc = prepare(%(<row r="1"><c r="A1" t="inlineStr"><is><t> {{ items:each(item) }} </t></is></c></row>))
    assert_equal ['items:each(item)'], @parser.parse_fields(doc).map(&:expression)
    assert_equal '1', cell(doc)['sablon-w']
  end

  def test_ignores_other_cells
    rows = %(<row r="1"><c r="A1"><v>1</v></c><c r="B1" t="str"><f>"{{=a}}"</f><v>{{=a}}</v></c>) +
           %(<c r="C1" t="inlineStr"><is><t>{{ not a field }}</t></is></c><c r="D1" t="s"><v>0</v></c></row>)
    original = Nokogiri::XML(sheet_xml(rows)).to_xml
    doc = prepare(rows, shared_strings('<si><t>no fields</t></si>'))
    assert_equal original, doc.to_xml
    assert_equal [], @parser.parse_fields(doc)
  end

  def test_parse_fields_in_document_order
    rows = %(<row r="1"><c r="A1" t="inlineStr"><is><t>{{a:each(x)}}</t></is></c></row>) +
           %(<row r="2"><c r="A2" t="inlineStr"><is><t>{{=x.a}} and {{=x.b}}</t></is></c></row>) +
           %(<row r="3"><c r="A3" t="inlineStr"><is><t>{{a:endEach}}</t></is></c></row>)
    fields = @parser.parse_fields(prepare(rows))
    assert_equal ['a:each(x)', '=x.a', '=x.b', 'a:endEach'], fields.map(&:expression)
    assert_equal [true, false, false, true], fields.map(&:whole_cell?)
    assert_equal ['1:1:0', '2:1:0', '2:1:1', '3:1:0'], fields.map(&:key)
  end

  def test_replace_with_text
    field = field_for('Hello {{=name}}')
    field.replace(Sablon.content(:string, ' _x0041_ & <b>'), @env)
    assert_equal %(<r><t xml:space="preserve"> _x005F_x0041_ &amp; &lt;b&gt;</t></r>), xml(field.run)
  end

  def test_replace_with_unsupported_content
    field = field_for('{{=name}}')
    e = assert_raises(Sablon::ContextError) do
      field.replace_value(Sablon.content(:html, '<b>bold</b>'), @env)
    end
    assert_match(/Spreadsheets only support inserting text and values/, e.message)
  end

  def test_replace_value_with_native_values
    field = field_for('{{=value}}')
    field.replace_value(12.5, @env)
    assert_equal %(<c r="A1"><v>12.5</v></c>), xml(field.cell)
    field = field_for('{{=value}}')
    field.replace_value(false, @env)
    assert_equal %(<c r="A1" t="b"><v>0</v></c>), xml(field.cell)
  end

  def test_replace_value_inserts_text_into_mixed_cells
    field = field_for('Total: {{=value}}')
    field.replace_value(12.5, @env)
    assert_equal 'Total: 12.5', field.cell.text
    field = field_for('Total: {{=value}}')
    field.replace_value(false, @env)
    assert_equal 'Total: ', field.cell.text
  end

  def test_replace_value_with_nil_removes_the_placeholder
    field = field_for('{{=value}}')
    field.replace_value(nil, @env)
    assert_nil field.run.parent
  end

  def test_remove_parent_respects_reference_counts
    doc = prepare(%(<row r="1"><c r="A1" t="inlineStr"><is><t>{{a:else}}</t></is></c></row>))
    field = @parser.parse_fields(doc).first
    field.block_reference_count = 2
    field.remove_parent(:row)
    assert field.row.parent, 'row should not have been removed yet'
    field.remove_parent(:row)
    assert_nil field.row.parent
  end

  private

  def sheet_xml(rows)
    %(<worksheet xmlns="#{NS}"><sheetData>#{rows}</sheetData></worksheet>)
  end

  def prepare(rows, strings = nil)
    doc = Nokogiri::XML(sheet_xml(rows))
    rows = doc.root.at_xpath('x:sheetData', 'x' => NS).element_children
    @parser.prepare_cells(rows, strings) { |c| Sablon::Spreadsheet::CellReference.parse(c['r']) }
    doc
  end

  def shared_strings(items)
    Sablon::DOM::SharedStrings.new(Nokogiri::XML(%(<sst xmlns="#{NS}">#{items}</sst>)))
  end

  def field_for(text)
    doc = prepare(%(<row r="1"><c r="A1" t="inlineStr"><is><t>#{text}</t></is></c></row>))
    @parser.parse_fields(doc).first
  end

  def cell(doc)
    doc.at_xpath('//x:c', 'x' => NS)
  end

  def xml(node)
    node.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML).gsub(%( xmlns="#{NS}"), '')
  end
end
