# Builds minimal spreadsheet packages for tests. The generated XML mirrors
# the structure written by Microsoft Excel and is valid according to the
# Office Open XML schemas.
class XlsxBuilder
  MAIN_NS = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'.freeze
  REL_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'.freeze
  PKG_REL_NS = 'http://schemas.openxmlformats.org/package/2006/relationships'.freeze
  REL_TYPE = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'.freeze
  CT_PREFIX = 'application/vnd.openxmlformats-officedocument.spreadsheetml'.freeze
  # Order of the worksheet child elements required by the schema
  WORKSHEET_ORDER = %w[sheetPr dimension sheetViews sheetFormatPr cols sheetData sheetCalcPr
                       sheetProtection protectedRanges scenarios autoFilter sortState
                       dataConsolidate customSheetViews mergeCells phoneticPr
                       conditionalFormatting dataValidations hyperlinks printOptions
                       pageMargins pageSetup headerFooter rowBreaks colBreaks customProperties
                       cellWatches ignoredErrors smartTags drawing legacyDrawing legacyDrawingHF
                       drawingHF picture oleObjects controls webPublishItems tableParts
                       extLst].freeze

  Sheet = Struct.new(:name, :rows, :before, :after, :rels)

  attr_accessor :shared_strings, :defined_names, :date1904, :calc_chain

  def initialize
    @sheets = []
    @parts = {}
    @overrides = {}
    @shared_strings = []
    @defined_names = []
    @date1904 = false
    @calc_chain = false
  end

  # +rows+ is the inner XML of sheetData. +before+ and +after+ contain the
  # elements before (i.e. cols) and after sheetData, they are sorted into
  # the order required by the schema. +rels+ is an array of [type, target]
  # relationships of the sheet.
  def add_sheet(name, rows, before: '', after: '', rels: [])
    @sheets << Sheet.new(name, rows, before, after, rels)
    self
  end

  def add_part(name, content, content_type = nil)
    @parts[name] = content
    @overrides[name] = content_type if content_type
    self
  end

  def entries
    entries = {}
    entries['[Content_Types].xml'] = content_types
    entries['_rels/.rels'] = rels([['officeDocument', 'xl/workbook.xml']])
    entries['xl/workbook.xml'] = workbook
    entries['xl/_rels/workbook.xml.rels'] = rels(workbook_rels)
    entries['xl/styles.xml'] = styles
    entries['xl/sharedStrings.xml'] = shared_strings_xml unless @shared_strings.empty?
    entries['xl/calcChain.xml'] = calc_chain_xml if calc_chain?
    @sheets.each_with_index do |sheet, index|
      entries["xl/worksheets/sheet#{index + 1}.xml"] = worksheet(sheet)
      next if sheet.rels.empty?
      entries["xl/worksheets/_rels/sheet#{index + 1}.xml.rels"] = rels(sheet.rels)
    end
    entries.merge(@parts)
  end

  def write(path)
    File.binwrite(path, to_s)
    path
  end

  def to_s
    Zip::OutputStream.write_buffer(StringIO.new) do |out|
      entries.each do |name, content|
        out.put_next_entry(name)
        out.write(content)
      end
    end.string
  end

  # Reads all entries of a package, XML is parsed
  def self.read(data)
    data = File.binread(data) unless data.start_with?('PK')
    entries = {}
    Zip::InputStream.open(StringIO.new(data)) do |io|
      while (entry = io.get_next_entry)
        next unless entry.file?
        content = io.read
        entries[entry.name] = entry.name =~ /\.(xml|rels)\z/ ? Nokogiri::XML(content) : content
      end
    end
    entries
  end

  private

  def declaration
    %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n)
  end

  def rels(list)
    items = list.each_with_index.map do |(type, target), index|
      type = "#{REL_TYPE}/#{type}" unless type.start_with?('http')
      %(<Relationship Id="rId#{index + 1}" Type="#{type}" Target="#{target}"/>)
    end
    %(#{declaration}<Relationships xmlns="#{PKG_REL_NS}">#{items.join}</Relationships>)
  end

  def workbook_rels
    list = @sheets.each_with_index.map { |_, index| ['worksheet', "worksheets/sheet#{index + 1}.xml"] }
    list << %w[styles styles.xml]
    list << %w[sharedStrings sharedStrings.xml] unless @shared_strings.empty?
    list << %w[calcChain calcChain.xml] if calc_chain?
    list
  end

  def content_types
    overrides = { 'xl/workbook.xml' => "#{CT_PREFIX}.sheet.main+xml",
                  'xl/styles.xml' => "#{CT_PREFIX}.styles+xml" }
    overrides['xl/sharedStrings.xml'] = "#{CT_PREFIX}.sharedStrings+xml" unless @shared_strings.empty?
    overrides['xl/calcChain.xml'] = "#{CT_PREFIX}.calcChain+xml" if calc_chain?
    @sheets.each_index do |index|
      overrides["xl/worksheets/sheet#{index + 1}.xml"] = "#{CT_PREFIX}.worksheet+xml"
    end
    overrides.merge!(@overrides)
    items = overrides.map { |name, type| %(<Override PartName="/#{name}" ContentType="#{type}"/>) }
    %(#{declaration}<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">) +
      %(<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>) +
      %(<Default Extension="xml" ContentType="application/xml"/>) +
      %(<Default Extension="vml" ContentType="application/vnd.openxmlformats-officedocument.vmlDrawing"/>) +
      %(<Default Extension="png" ContentType="image/png"/>) +
      %(#{items.join}</Types>)
  end

  def workbook
    sheets = @sheets.each_with_index.map do |sheet, index|
      %(<sheet name="#{sheet.name}" sheetId="#{index + 1}" r:id="rId#{index + 1}"/>)
    end
    names = @defined_names.map do |name, value, local|
      local_attr = local.nil? ? '' : %( localSheetId="#{local}")
      %(<definedName name="#{name}"#{local_attr}>#{value.encode(xml: :text)}</definedName>)
    end
    names = names.empty? ? '' : "<definedNames>#{names.join}</definedNames>"
    %(#{declaration}<workbook xmlns="#{MAIN_NS}" xmlns:r="#{REL_NS}">) +
      %(<workbookPr#{@date1904 ? ' date1904="1"' : ''} defaultThemeVersion="164011"/>) +
      %(<bookViews><workbookView xWindow="0" yWindow="0" windowWidth="28800" windowHeight="12300"/></bookViews>) +
      %(<sheets>#{sheets.join}</sheets>#{names}<calcPr calcId="191029"/></workbook>)
  end

  # style 0: default, 1: date (numFmtId 14), 2: bold font, 3: currency
  # differential style 0 (conditional formatting): red text on red fill
  def styles
    %(#{declaration}<styleSheet xmlns="#{MAIN_NS}">) +
      %(<numFmts count="1"><numFmt numFmtId="164" formatCode="&quot;$&quot;#,##0.00"/></numFmts>) +
      %(<fonts count="2"><font><sz val="11"/><name val="Calibri"/><family val="2"/></font>) +
      %(<font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font></fonts>) +
      %(<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>) +
      %(<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>) +
      %(<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>) +
      %(<cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>) +
      %(<xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>) +
      %(<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>) +
      %(<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>) +
      %(<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>) +
      %(<dxfs count="1"><dxf><font><color rgb="FF9C0006"/></font>) +
      %(<fill><patternFill><bgColor rgb="FFFFC7CE"/></patternFill></fill></dxf></dxfs>) +
      %(</styleSheet>)
  end

  def shared_strings_xml
    items = @shared_strings.map do |item|
      item.start_with?('<') ? "<si>#{item}</si>" : %(<si><t xml:space="preserve">#{item.encode(xml: :text)}</t></si>)
    end
    %(#{declaration}<sst xmlns="#{MAIN_NS}" count="#{items.length}" uniqueCount="#{items.length}">#{items.join}</sst>)
  end

  # The calculation chain may only list cells containing formulas
  def calc_chain?
    @calc_chain && !formula_cells.empty?
  end

  def formula_cells
    @sheets.each_with_index.flat_map do |sheet, index|
      Nokogiri::XML("<sheetData>#{sheet.rows}</sheetData>").xpath('//c[f]').map do |cell|
        [cell['r'], index + 1]
      end
    end
  end

  def calc_chain_xml
    cells = formula_cells.map { |ref, sheet_id| %(<c r="#{ref}" i="#{sheet_id}"/>) }
    %(#{declaration}<calcChain xmlns="#{MAIN_NS}">#{cells.join}</calcChain>)
  end

  def worksheet(sheet)
    xml = %(#{declaration}<worksheet xmlns="#{MAIN_NS}" xmlns:r="#{REL_NS}" ) +
          %(xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" ) +
          %(xmlns:x14ac="http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac" mc:Ignorable="x14ac">) +
          %(<dimension ref="A1"/><sheetViews><sheetView workbookViewId="0"/></sheetViews>) +
          %(<sheetFormatPr defaultRowHeight="15" x14ac:dyDescent="0.25"/>#{sheet.before}) +
          %(<sheetData>#{sheet.rows}</sheetData>#{sheet.after}) +
          %(<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/></worksheet>)
    doc = Nokogiri::XML(xml)
    children = doc.root.element_children.each_with_index.sort_by do |node, index|
      position = WORKSHEET_ORDER.index(node.name)
      raise ArgumentError, "Unknown worksheet element: #{node.name}" unless position
      [position, index]
    end
    children.each { |node, _| doc.root.add_child(node) }
    doc.to_xml(indent: 0, save_with: 0)
  end
end

# Helpers to write the cells of test worksheets
module XlsxCells
  def row(number, *cells)
    %(<row r="#{number}">#{cells.join}</row>)
  end

  def text(ref, value, style = nil)
    %(<c r="#{ref}"#{style_attr(style)} t="inlineStr"><is><t>#{value.encode(xml: :text)}</t></is></c>)
  end

  def shared(ref, index, style = nil)
    %(<c r="#{ref}"#{style_attr(style)} t="s"><v>#{index}</v></c>)
  end

  def number(ref, value, style = nil)
    %(<c r="#{ref}"#{style_attr(style)}><v>#{value}</v></c>)
  end

  def formula(ref, value, style = nil)
    %(<c r="#{ref}"#{style_attr(style)}><f>#{value.encode(xml: :text)}</f><v>0</v></c>)
  end

  def style_attr(style)
    style ? %( s="#{style}") : ''
  end
end

# Helpers to render templates built with XlsxBuilder and inspect the result
module XlsxRendering
  SANDBOX = File.expand_path('../../sandbox', __FILE__)

  def render_xlsx(builder, context, name = 'xlsx_test')
    path = File.join(SANDBOX, "#{name}_template.xlsx")
    builder.write(path)
    XlsxBuilder.read(Sablon.template(path).render_to_string(context))
  end

  # Returns a hash of cell references and values: strings for text, numbers
  # as strings, "=..." for formulas, true/false for booleans and nil for
  # blank cells.
  def cell_values(entries, sheet = 1)
    doc = entries["xl/worksheets/sheet#{sheet}.xml"]
    strings = entries['xl/sharedStrings.xml']
    ns = { 'x' => XlsxBuilder::MAIN_NS }
    doc.xpath('//x:sheetData/x:row/x:c', ns).each_with_object({}) do |cell, values|
      values[cell['r']] = cell_value(cell, strings, ns)
    end
  end

  def cell_value(cell, strings, ns)
    formula = cell.at_xpath('x:f', ns)
    value = cell.at_xpath('x:v', ns)
    case
    when formula then "=#{formula.text}"
    when cell['t'] == 'inlineStr' then cell.xpath('x:is//x:t', ns).map(&:text).join
    when cell['t'] == 's' then strings.xpath('//x:si', ns)[value.text.to_i].xpath('.//x:t', ns).map(&:text).join
    when cell['t'] == 'b' then value.text == '1'
    when value then value.text
    end
  end

  def sheet_xml(entries, sheet = 1)
    entries["xl/worksheets/sheet#{sheet}.xml"].to_xml
  end
end
