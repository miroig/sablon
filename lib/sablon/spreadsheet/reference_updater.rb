require 'sablon/spreadsheet/cell_reference'
require 'sablon/spreadsheet/formula'

module Sablon
  module Spreadsheet
    # Applies the PositionMap of a rendered worksheet to all references
    # pointing to the worksheet.
    class ReferenceUpdater
      MAIN_NS = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'.freeze
      EXCEL_NS = 'http://schemas.microsoft.com/office/excel/2006/main'.freeze
      CHART_NS = 'http://schemas.openxmlformats.org/drawingml/2006/chart'.freeze
      # chart elements containing the data of a series
      CHART_DATA = %w[cat val xVal yVal bubbleSize].freeze
      CHART_CACHES = %w[numCache strCache multiLvlStrCache].freeze

      def initialize(map, sheet_name)
        @map = map
        @sheet_name = sheet_name && sheet_name.downcase
      end

      # Rewrites the references to the sheet within formula text. Unqualified
      # references are only rewritten when +local+ is true. +context+ holds
      # the tokens of the cell containing the formula, see
      # PositionMap#map_reference for the +mode+.
      def formula(text, local, context = nil, mode = :formula)
        Formula.rewrite(text) do |ref|
          @map.map_reference(ref, context, mode) if target?(ref, local)
        end
      end

      def targets?(text, local)
        Formula.references(text).any? { |ref| target?(ref, local) }
      end

      # Rewrites a list of cells and ranges ("sqref") of the sheet itself.
      # Returns an empty string if all cells have been removed.
      def sqref(text)
        Formula.rewrite_sqref(text) do |ref|
          @map.map_reference(ref, nil, :area) if target?(ref, true)
        end
      end

      # Updates the formulas of the cells in the rendered worksheet itself
      def update_cell_formulas(sheet_data, layout)
        sheet_data.xpath('./x:row/x:c/x:f', 'x' => sheet_data.namespace.href).each do |node|
          context = layout.context(node.parent)
          node.content = formula(node.text, true, context) unless node.text.empty?
          %w[ref r1 r2].each do |attr|
            node[attr] = formula(node[attr], true, context) if node[attr]
          end
        end
      end

      # Updates references within the formulas of another worksheet
      def update_other_sheet(doc)
        doc.xpath('//x:sheetData/x:row/x:c/x:f', 'x' => namespace(doc)).each do |node|
          node.content = formula(node.text, false) unless node.text.empty?
        end
        update_rule_formulas(doc, false)
      end

      # Updates conditional formatting, data validation and auto filter
      # ranges as well as formulas used by them in the rendered worksheet.
      def update_sheet_ranges(doc)
        ns = { 'x' => namespace(doc), 'xm' => EXCEL_NS }
        update_rule_formulas(doc, true)
        doc.xpath('/x:worksheet/x:conditionalFormatting[@sqref]', ns).each do |node|
          update_sqref_attribute(node, node)
        end
        validations = doc.at_xpath('/x:worksheet/x:dataValidations', ns)
        if validations
          validations.xpath('./x:dataValidation[@sqref]', ns).each { |node| update_sqref_attribute(node, node) }
          validations['count'] = validations.element_children.length.to_s if validations['count']
          validations.remove if validations.element_children.empty?
        end
        doc.xpath('//xm:sqref', ns).each do |node|
          value = sqref(node.text)
          next node.content = value unless value.empty?
          node.parent.remove
        end
        doc.xpath('/x:worksheet/x:autoFilter', ns).each { |node| update_filter(node) }
      end

      def update_defined_names(names)
        names.each do |node|
          node.content = formula(node.text, false) unless node.text.empty?
        end
      end

      # Updates the data references of a chart. Cached values of updated
      # references are removed, they are restored by spreadsheet
      # applications when the chart is displayed.
      def update_chart(doc)
        doc.xpath('//c:f', 'c' => CHART_NS).each do |node|
          next unless targets?(node.text, false)
          data = node.ancestors.any? { |parent| CHART_DATA.include?(parent.name) }
          node.content = formula(node.text, false, nil, data ? :area : :first)
          node.parent.element_children.each do |sibling|
            sibling.remove if CHART_CACHES.include?(sibling.name)
          end
        end
      end

      # Updates the range of a table. Column loops can't be used within
      # tables because the table columns would need to change.
      def update_table(doc, sheet_doc)
        table = doc.root
        ref = Formula.references(table['ref']).first
        return unless ref && ref.kind == :range
        if @map.column_changes?(ref.row1, ref.row2, ref.col1, ref.col2)
          raise TemplateError, "Column loops are not supported within the table '#{table['displayName']}'"
        end
        #
        new_ref = sqref(table['ref'])
        return if new_ref.empty?
        table['ref'] = new_ref
        table.element_children.each { |node| update_filter(node) if node.name == 'autoFilter' }
        update_table_columns(table, sheet_doc)
      end

      # Moves pictures, shapes and charts anchored to cells
      def update_drawing(doc)
        anchors = doc.xpath('//*[local-name() = "twoCellAnchor" or local-name() = "oneCellAnchor"]')
        anchors.each do |anchor|
          next if anchor['editAs'] == 'absolute'
          from = marker(anchor, 'from')
          next unless from
          new_from = @map.point(from[0], from[1])
          write_marker(anchor, 'from', new_from)
          to = marker(anchor, 'to')
          next unless to
          new_to = if anchor['editAs'] == 'oneCell'
                     [to[0] + new_from[0] - from[0], to[1] + new_from[1] - from[1]]
                   else
                     @map.point(to[0], to[1])
                   end
          write_marker(anchor, 'to', [[new_to[0], new_from[0]].max, [new_to[1], new_from[1]].max])
        end
      end

      # Moves the comments (notes) of the sheet, comments of removed cells
      # are deleted. Returns the template cells of the deleted comments.
      def update_comments(doc, xpath)
        removed = []
        doc.xpath(xpath).each do |node|
          pos = CellReference.parse(node['ref'])
          next unless pos
          new_pos = @map.first(pos[0], pos[1])
          if new_pos
            node['ref'] = CellReference.format(new_pos[0], new_pos[1])
          else
            removed << pos
            node.remove
          end
        end
        removed
      end

      # Moves the shapes of legacy notes stored in VML drawings. VML is
      # edited as text because it is not always well formed XML.
      def update_vml(vml)
        vml.gsub(%r{<v:shape\b.*?</v:shape>}m) do |shape|
          row = shape[%r{<x:Row>(\d+)</x:Row>}, 1]
          col = shape[%r{<x:Column>(\d+)</x:Column>}, 1]
          next shape unless shape.include?('ObjectType="Note"') && row && col
          #
          old_pos = [row.to_i + 1, col.to_i + 1]
          new_pos = @map.first(*old_pos)
          next '' unless new_pos
          move_vml_shape(shape, new_pos[0] - old_pos[0], new_pos[1] - old_pos[1])
        end
      end

      private

      def namespace(doc)
        doc.root && doc.root.namespace ? doc.root.namespace.href : MAIN_NS
      end

      def target?(ref, local)
        case ref.scope
        when :local
          local
        when :sheet
          !@sheet_name.nil? && ref.sheet.downcase == @sheet_name
        else
          false
        end
      end

      # Formulas of conditional formatting rules, data validations and
      # Excel 2010 extensions (xm:f). They are relative to the first cell
      # of the range they apply to.
      def update_rule_formulas(doc, local)
        ns = { 'x' => namespace(doc), 'xm' => EXCEL_NS }
        selectors = ['/x:worksheet/x:conditionalFormatting/x:cfRule/x:formula',
                     '/x:worksheet/x:dataValidations/x:dataValidation/x:formula1',
                     '/x:worksheet/x:dataValidations/x:dataValidation/x:formula2',
                     '//xm:f']
        doc.xpath(selectors.join(' | '), ns).each do |node|
          node.content = formula(node.text, local, nil, :first) unless node.text.empty?
        end
      end

      def update_sqref_attribute(node, removable)
        value = sqref(node['sqref'])
        return node['sqref'] = value unless value.empty?
        removable.remove
      end

      def update_filter(node)
        update_ref_attribute(node)
        node.xpath('.//*[@ref]').each { |child| update_ref_attribute(child) }
      end

      def update_ref_attribute(node)
        value = sqref(node['ref'])
        node['ref'] = value unless value.empty?
      end

      # Header cells and table column names need to match
      def update_table_columns(table, sheet_doc)
        return if table['headerRowCount'] == '0' || sheet_doc.nil?
        ref = Formula.references(table['ref']).first
        columns = table.element_children.detect { |node| node.name == 'tableColumns' }
        return unless columns
        ns = { 'x' => namespace(sheet_doc) }
        columns.element_children.each_with_index do |column, index|
          address = CellReference.format(ref.row1, ref.col1 + index)
          cell = sheet_doc.at_xpath("//x:sheetData/x:row/x:c[@r='#{address}']", ns)
          text = cell && inline_text(cell)
          column['name'] = text if text && !text.empty?
        end
      end

      # Text of cells that have been changed by the rendering process
      def inline_text(cell)
        case cell['t']
        when 'inlineStr'
          cell.xpath('./*[local-name() = "is"]//*[local-name() = "t"]').map(&:text).join
        when nil, 'n'
          value = cell.element_children.detect { |node| node.name == 'v' }
          value.text if value && cell.element_children.none? { |node| node.name == 'f' }
        end
      end

      # Returns the 1 based [row, column] of a drawing anchor marker
      def marker(anchor, name)
        node = anchor.element_children.detect { |child| child.name == name }
        return unless node
        row = node.element_children.detect { |child| child.name == 'row' }
        col = node.element_children.detect { |child| child.name == 'col' }
        [row.text.to_i + 1, col.text.to_i + 1] if row && col
      end

      def write_marker(anchor, name, pos)
        node = anchor.element_children.detect { |child| child.name == name }
        node.element_children.each do |child|
          child.content = (pos[0] - 1).to_s if child.name == 'row'
          child.content = (pos[1] - 1).to_s if child.name == 'col'
        end
      end

      def move_vml_shape(shape, drow, dcol)
        shape = shape.sub(%r{<x:Row>(\d+)</x:Row>}) { "<x:Row>#{Regexp.last_match(1).to_i + drow}</x:Row>" }
        shape = shape.sub(%r{<x:Column>(\d+)</x:Column>}) { "<x:Column>#{Regexp.last_match(1).to_i + dcol}</x:Column>" }
        shape.sub(%r{<x:Anchor>([^<]*)</x:Anchor>}) do
          values = Regexp.last_match(1).split(',').map(&:strip)
          next Regexp.last_match(0) unless values.length == 8
          # left column, offset, top row, offset, right column, offset, bottom row, offset
          [0, 4].each { |i| values[i] = (values[i].to_i + dcol).to_s }
          [2, 6].each { |i| values[i] = (values[i].to_i + drow).to_s }
          "<x:Anchor>#{values.join(', ')}</x:Anchor>"
        end
      end
    end
  end
end
