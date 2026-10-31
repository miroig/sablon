require 'pathname'
require 'sablon/spreadsheet/cell_reference'
require 'sablon/spreadsheet/formula'
require 'sablon/spreadsheet/layout'
require 'sablon/spreadsheet/reference_updater'

module Sablon
  module Spreadsheet
    # Coordinates the processing of the parts of a spreadsheet template. It
    # prepares the workbook once before any worksheet is rendered and keeps
    # all references to a worksheet consistent after it has been rendered.
    class Package
      WORKBOOK = Sablon::DOM::Workbook::ENTRY_NAME

      def initialize(model)
        @model = model
        @prepared = false
      end

      def workbook
        handler = @model[WORKBOOK]
        handler if handler.is_a?(Sablon::DOM::Workbook)
      end

      def date1904?
        workbook && workbook.date1904? ? true : false
      end

      def shared_strings
        return @shared_strings if defined?(@shared_strings)
        entry = related(WORKBOOK, 'sharedStrings').map(&:last).first
        handler = entry && @model[entry]
        @shared_strings = if handler.is_a?(Sablon::DOM::SharedStrings)
                            handler
                          elsif entry && xml(entry)
                            Sablon::DOM::SharedStrings.new(xml(entry))
                          end
      end

      # Hash of worksheet entry names and sheet names
      def worksheets
        @worksheets ||= begin
          targets = Hash[related(WORKBOOK, 'worksheet')]
          sheets = workbook ? workbook.sheets : []
          Hash[sheets.map { |sheet| [targets[sheet.rid], sheet.name] }.reject { |entry, _| entry.nil? }]
        end
      end

      def sheet_name(entry)
        worksheets[entry]
      end

      # Prepares all worksheets before the first one is rendered: shared
      # formulas are expanded so formulas can be moved independently and
      # cached results are removed. The calculation chain is deleted and
      # applications are told to recalculate the workbook when it is opened.
      def prepare!
        return if @prepared
        @prepared = true
        worksheets.each_key do |entry|
          doc = xml(entry)
          next unless doc
          sheet_data = doc.at_xpath('/*/*[local-name() = "sheetData"]')
          next unless sheet_data
          Layout.normalize(sheet_data)
          expand_shared_formulas(sheet_data)
          remove_cached_values(sheet_data)
        end
        remove_calc_chain
        workbook.full_calc_on_load! if workbook
      end

      # Updates all references to a rendered worksheet
      def update_references(entry, map)
        return if map.identity?
        updater = ReferenceUpdater.new(map, sheet_name(entry))
        worksheets.each_key do |other|
          next if other == entry || xml(other).nil?
          updater.update_other_sheet(xml(other))
        end
        updater.update_defined_names(workbook.defined_names) if workbook
        @model.zip_contents.each_key do |name|
          updater.update_chart(xml(name)) if name =~ %r{^xl/charts/chart[^/]*\.xml$} && xml(name)
        end
        update_sheet_parts(entry, updater)
      end

      # Excel tables need at least one data row. When blocks remove all data
      # rows of a table an empty row is kept below the header, the same way
      # Excel does when all rows of a table are deleted. Called with the
      # template positions before the worksheet is renumbered.
      def keep_table_rows(entry, layout)
        related(entry, 'table').each do |_, part|
          table = xml(part) && xml(part).root
          ref = table && Formula.references(table['ref']).first
          next unless ref && ref.kind == :range
          header = (table['headerRowCount'] || 1).to_i
          first_data = ref.row1 + header
          last_data = ref.row2 - table['totalsRowCount'].to_i
          next if first_data > last_data || layout.rows_remain?(first_data, last_data)
          next if header > 0 && !layout.rows_remain?(ref.row1, first_data - 1)
          layout.keep_row(first_data)
        end
      end

      # Returns [relationship id, entry name] pairs of the parts related to
      # +entry+ by a relationship type ending with "/type".
      def related(entry, type)
        rels = xml(Sablon::DOM::Relationships.rels_entry_name_for(entry))
        return [] unless rels && rels.root
        rels.root.element_children.each_with_object([]) do |rel, parts|
          next unless rel['Type'].to_s.end_with?("/#{type}") && rel['TargetMode'] != 'External'
          parts << [rel['Id'], resolve(entry, rel['Target'].to_s)]
        end
      end

      private

      def xml(entry)
        content = @model.zip_contents[entry]
        content if content.is_a?(Nokogiri::XML::Document)
      end

      def resolve(entry, target)
        return target[1..-1] if target.start_with?('/')
        Pathname.new(File.dirname(entry)).join(target).cleanpath.to_s
      end

      def update_sheet_parts(entry, updater)
        renames = {}
        related(entry, 'table').each do |rid, table|
          next unless xml(table)
          if updater.table_removed?(xml(table))
            remove_table(entry, rid, table)
          else
            columns = updater.update_table(xml(table), xml(entry))
            name = xml(table).root['displayName'] || xml(table).root['name']
            renames[name.downcase] = columns if name && !columns.empty?
          end
        end
        rename_table_columns(renames) unless renames.empty?
        related(entry, 'drawing').each do |_, drawing|
          updater.update_drawing(xml(drawing)) if xml(drawing)
        end
        related(entry, 'comments').each do |_, comments|
          updater.update_comments(xml(comments), '//*[local-name() = "comment"]') if xml(comments)
        end
        related(entry, 'threadedComment').each do |_, comments|
          updater.update_comments(xml(comments), '//*[local-name() = "threadedComment"]') if xml(comments)
        end
        related(entry, 'vmlDrawing').each do |_, vml|
          content = @model.zip_contents[vml]
          @model.zip_contents[vml] = updater.update_vml(content) if content.is_a?(String)
        end
      end

      # Updates the structured references to renamed table columns in all
      # formulas of the workbook.
      def rename_table_columns(renames)
        nodes = []
        worksheets.each_key do |sheet|
          doc = xml(sheet)
          nodes.concat(doc.xpath('/*/*[local-name() = "sheetData"]/*/*/*[local-name() = "f"]').to_a) if doc
          related(sheet, 'table').each do |_, table|
            next unless xml(table)
            nodes.concat(xml(table).xpath('//*[local-name() = "calculatedColumnFormula" or ' \
                                          'local-name() = "totalsRowFormula"]').to_a)
          end
        end
        nodes.concat(workbook.defined_names.to_a) if workbook
        @model.zip_contents.each_key do |name|
          next unless name =~ %r{^xl/charts/chart[^/]*\.xml$} && xml(name)
          nodes.concat(xml(name).xpath('//*[local-name() = "f"]').to_a)
        end
        nodes.each do |node|
          node.content = Formula.rename_columns(node.text, renames) unless node.text.empty?
        end
      end

      # Shared formulas are stored once and reused by other cells, every
      # cell gets its own copy of the formula translated to its position.
      def expand_shared_formulas(sheet_data)
        formulas = sheet_data.xpath('./*/*/*[local-name() = "f"][@t = "shared"]')
        masters = {}
        formulas.each do |node|
          next if node.text.empty? || masters[node['si']]
          masters[node['si']] = [node.text, CellReference.parse(node.parent['r'])]
        end
        formulas.each do |node|
          text, origin = masters[node['si']]
          if node.text.empty? && text && origin
            pos = CellReference.parse(node.parent['r'])
            node.content = Formula.translate(text, pos[0] - origin[0], pos[1] - origin[1])
          end
          %w[t si ref].each { |attr| node.remove_attribute(attr) }
        end
      end

      def remove_cached_values(sheet_data)
        sheet_data.xpath('./*/*[*[local-name() = "f"]]').each do |cell|
          cell.element_children.each { |node| node.remove if node.name == 'v' }
          cell.remove_attribute('t')
        end
      end

      def remove_calc_chain
        related(WORKBOOK, 'calcChain').each do |rid, entry|
          remove_part(WORKBOOK, rid, entry)
        end
      end

      # Tables whose header row has been removed by a block are deleted
      def remove_table(entry, rid, part)
        remove_part(entry, rid, part)
        @model.zip_contents.delete(Sablon::DOM::Relationships.rels_entry_name_for(part))
        parts = xml(entry).at_xpath('/*/*[local-name() = "tableParts"]')
        return unless parts
        parts.element_children.each do |node|
          node.remove if node.attributes.values.any? { |attr| attr.name == 'id' && attr.value == rid }
        end
        return parts.remove if parts.element_children.empty?
        parts['count'] = parts.element_children.length.to_s
      end

      # Removes a part, the relationship pointing to it and its content type
      def remove_part(source, rid, part)
        @model.zip_contents.delete(part)
        rels = xml(Sablon::DOM::Relationships.rels_entry_name_for(source))
        rels.root.element_children.each { |rel| rel.remove if rel['Id'] == rid }
        content_types = xml('[Content_Types].xml')
        return unless content_types
        content_types.root.element_children.each do |node|
          node.remove if node['PartName'] == "/#{part}"
        end
      end
    end
  end
end
