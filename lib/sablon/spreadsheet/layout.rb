require 'sablon/spreadsheet/cell_reference'
require 'sablon/spreadsheet/position_map'

module Sablon
  module Spreadsheet
    # Keeps track of the template positions of rows and cells while a
    # worksheet is rendered and assigns the final row and cell numbers.
    #
    # The rows between the first and last row containing placeholders form
    # the region of the worksheet that can change. Empty template positions
    # inside of the region are filled with placeholder nodes so that gaps
    # between rows or cells are retained when they are copied. The template
    # row and cell numbers ("r" attributes) are kept until rendering is done
    # and identify the origin of every generated row and cell.
    class Layout
      FILLER = 'sablon-ph'.freeze
      TOKENS = 'sablon-t'.freeze
      COLUMN_REGION = 'sablon-c'.freeze
      ANNOTATIONS = [FILLER, TOKENS, COLUMN_REGION,
                     Sablon::Parser::Worksheet::CELL_MARKER,
                     Sablon::Parser::Worksheet::WHOLE_CELL_MARKER].freeze

      class << self
        # Records the block iteration that generated the node
        def stamp(node, block, copy, index)
          node[TOKENS] = ["#{block}|#{copy}|#{index}", node[TOKENS]].compact.join(' ')
        end

        def next_copy_id
          @copy_mutex.synchronize { @copy_id += 1 }
        end

        # Assigns explicit numbers to rows and cells that don't define them
        def normalize(sheet_data)
          prev_row = 0
          sheet_data.element_children.each do |row|
            next unless row.name == 'row'
            number = row['r'] ? row['r'].to_i : prev_row + 1
            row['r'] = number.to_s unless row['r']
            prev_col = 0
            row.element_children.each do |cell|
              next unless cell.name == 'c'
              pos = cell['r'] && CellReference.parse(cell['r'])
              col = pos ? pos[1] : prev_col + 1
              cell['r'] = CellReference.format(number, col) unless pos
              prev_col = col
            end
            prev_row = number
          end
        end
      end
      @copy_mutex = Mutex.new
      @copy_id = 0

      attr_reader :first_row, :last_row

      def initialize(sheet_data)
        @sheet_data = sheet_data
        @token_cache = {}
      end

      def changes?
        !@first_row.nil?
      end

      # Converts the placeholder cells and annotates the region. Returns the
      # number of shared string references that have been replaced.
      def prepare(parser, shared_strings)
        self.class.normalize(@sheet_data)
        rows = row_nodes
        shared = 0
        cells = parser.prepare_cells(rows, shared_strings) do |cell|
          shared += 1 if cell['t'] == 's'
          position(cell)
        end
        return shared if cells.empty?
        #
        @first_row, @last_row = cells.map { |cell| row_number(cell.parent) }.minmax
        fill_rows(rows)
        cells.group_by(&:parent).each { |row, row_cells| fill_cells(row, row_cells) }
        shared
      end

      # Assigns the final row and cell numbers and returns the PositionMap
      def finalize
        return PositionMap.identity unless changes?
        rows = row_nodes
        in_region = rows.count { |row| region_row?(row) }
        delta = @first_row + in_region - (@last_row + 1)
        next_row = @first_row
        numbers = rows.map do |row|
          orig = row_number(row)
          if region_row?(row)
            (next_row += 1) - 1
          elsif orig > @last_row
            orig + delta
          else
            orig
          end
        end
        #
        entries = {}
        rows.each_with_index do |row, index|
          number = numbers[index]
          check_limit(number, CellReference::MAX_ROWS, 'rows')
          columns = assign_columns(row, number)
          if region_row?(row)
            (entries[row_number(row)] ||= []) << PositionMap::Entry.new(number, tokens(row), columns)
          end
          row['r'] = number.to_s
        end
        PositionMap.new(PositionMap::Axis.new(@first_row, @last_row, delta, entries))
      end

      # Returns the row and cell tokens of a cell
      def context(cell)
        [tokens(cell.parent), tokens(cell)]
      end

      # Removes placeholders and annotations and updates the cells
      # containing fields. Returns the [min_row, min_col, max_row, max_col]
      # of all cells.
      def cleanup
        box = nil
        row_nodes.each do |row|
          next row.remove if row[FILLER]
          region = row[COLUMN_REGION]
          strip(row)
          row.remove_attribute('spans') if region
          row.element_children.each do |cell|
            next unless cell.name == 'c'
            next cell.remove if cell[FILLER]
            finish_cell(cell) if cell[Sablon::Parser::Worksheet::CELL_MARKER]
            strip(cell)
            pos = position(cell)
            box = box ? [[box[0], pos[0]].min, [box[1], pos[1]].min, [box[2], pos[0]].max, [box[3], pos[1]].max] : pos + pos
          end
        end
        box
      end

      def tokens(node)
        value = node[TOKENS]
        return PositionMap::EMPTY unless value
        @token_cache[value] ||= value.split(' ').map do |token|
          block, copy, index = token.split('|')
          PositionMap::Token.new(block, copy.to_i, index.to_i)
        end
      end

      # true if any of the template rows between +from+ and +to+ is part of
      # the rendered worksheet. Rows outside of the region are never removed.
      def rows_remain?(from, to)
        return true if !changes? || from < @first_row || to > @last_row
        row_nodes.any? { |row| row_number(row).between?(from, to) }
      end

      # Keeps an empty row at the position of the removed template row
      def keep_row(number)
        node = filler('row', number.to_s)
        following = row_nodes.detect { |row| row_number(row) > number }
        following ? following.add_previous_sibling(node) : @sheet_data.add_child(node)
      end

      private

      def row_nodes
        @sheet_data.element_children.select { |node| node.name == 'row' }
      end

      def cell_nodes(row)
        row.element_children.select { |node| node.name == 'c' }
      end

      def row_number(row)
        row['r'].to_i
      end

      def position(cell)
        CellReference.parse(cell['r'])
      end

      def region_row?(row)
        number = row_number(row)
        number >= @first_row && number <= @last_row
      end

      # Adds placeholder rows for the missing rows inside of the region
      def fill_rows(rows)
        expected = @first_row
        rows.each do |row|
          number = row_number(row)
          next unless number >= @first_row && number <= @last_row
          while expected < number
            row.add_previous_sibling(filler('row', expected.to_s))
            expected += 1
          end
          expected = number + 1
        end
      end

      # Adds placeholder cells for missing cells between the first and the
      # last cell containing placeholders in a row.
      def fill_cells(row, placeholder_cells)
        first_col, last_col = placeholder_cells.map { |cell| position(cell)[1] }.minmax
        row[COLUMN_REGION] = "#{first_col}:#{last_col}"
        number = row_number(row)
        expected = first_col
        cell_nodes(row).each do |cell|
          col = position(cell)[1]
          next unless col >= first_col && col <= last_col
          while expected < col
            cell.add_previous_sibling(filler('c', CellReference.format(number, expected)))
            expected += 1
          end
          expected = col + 1
        end
      end

      def filler(name, ref)
        node = Nokogiri::XML::Node.new(name, @sheet_data.document)
        node['r'] = ref
        node[FILLER] = '1'
        node
      end

      # Assigns the final column numbers of the cells in a row and returns
      # the column axis if the row contains a column region.
      def assign_columns(row, number)
        cells = cell_nodes(row)
        unless row[COLUMN_REGION]
          cells.each { |cell| cell['r'] = CellReference.format(number, position(cell)[1]) }
          return
        end
        #
        first_col, last_col = row[COLUMN_REGION].split(':').map(&:to_i)
        in_region = cells.count { |cell| (first_col..last_col).cover?(position(cell)[1]) }
        delta = first_col + in_region - (last_col + 1)
        next_col = first_col
        entries = {}
        cells.each do |cell|
          orig = position(cell)[1]
          col = if orig < first_col
                  orig
                elsif orig > last_col
                  orig + delta
                else
                  (next_col += 1) - 1
                end
          check_limit(col, CellReference::MAX_COLUMNS, 'columns')
          if orig >= first_col && orig <= last_col
            (entries[orig] ||= []) << PositionMap::Entry.new(col, tokens(cell), nil)
          end
          cell['r'] = CellReference.format(number, col)
        end
        axis = PositionMap::Axis.new(first_col, last_col, delta, entries)
        axis if axis.changed?
      end

      def check_limit(value, max, name)
        return if value <= max
        raise ContextError, "The rendered worksheet exceeds the maximum number of #{name} (#{max})"
      end

      # Removes empty runs and merges plain runs of cells that contained
      # fields. Cells without any content left become blank cells.
      def finish_cell(cell)
        inline = cell.element_children.detect { |node| node.name == 'is' }
        return unless inline
        runs = inline.element_children.select { |node| node.name == 'r' }
        runs.select! do |run|
          run.remove_attribute(Sablon::Parser::Worksheet::FIELD_MARKER)
          run.remove_attribute(Sablon::Parser::Worksheet::FIELD_KEY)
          text = run.element_children.detect { |node| node.name == 't' }
          next true if text && !text.content.empty?
          run.remove
          false
        end
        if runs.empty?
          CellValue.clear(cell)
        elsif runs.none? { |run| run.element_children.any? { |node| node.name == 'rPr' } }
          text = runs.map { |run| run.element_children.detect { |node| node.name == 't' }.content }.join
          inline.children.each(&:remove)
          CellValue.text_element(inline, text)
        end
        check_text_length(cell, inline)
      end

      # Excel counts the length of cell text in UTF-16 code units
      def check_text_length(cell, inline)
        length = inline.xpath('.//*[local-name() = "t"]').inject(0) do |sum, node|
          sum + node.content.encode('UTF-16LE').bytesize / 2
        end
        return if length <= CellValue::MAX_TEXT_LENGTH
        raise ContextError, "The text of cell #{cell['r']} exceeds the maximum length of " \
                            "#{CellValue::MAX_TEXT_LENGTH} characters"
      end

      def strip(node)
        ANNOTATIONS.each { |name| node.remove_attribute(name) if node[name] }
      end
    end
  end
end
