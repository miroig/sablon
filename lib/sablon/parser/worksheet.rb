require 'sablon/spreadsheet/cell_value'

module Sablon
  module Parser
    # Locates the "{{...}}" placeholder fields of spreadsheet templates.
    #
    # Before fields can be parsed the cells of a worksheet need to be
    # prepared. Every string cell containing placeholders is converted into
    # an inline rich text string where each placeholder occupies its own run,
    # similar to the runs of a MailMerge field in a Word document.
    class Worksheet
      PLACEHOLDER = /\{\{\s*([^\s{}]+)\s*\}\}/
      WHOLE_CELL = /\A\s*\{\{\s*[^\s{}]+\s*\}\}\s*\z/
      # attributes used to annotate the template during processing, they are
      # removed before the worksheet is written.
      CELL_MARKER = 'sablon-p'.freeze
      WHOLE_CELL_MARKER = 'sablon-w'.freeze
      FIELD_MARKER = 'sablon-f'.freeze
      FIELD_KEY = 'sablon-k'.freeze

      # A placeholder inside of a cell
      class CellField
        attr_accessor :block_reference_count
        attr_reader :expression, :cell, :run

        def initialize(cell, run)
          @cell = cell
          @run = run
          @expression = run[FIELD_MARKER]
          @block_reference_count = 0
        end

        def valid?
          !(expression.nil? || expression.empty?)
        end

        # Unique key of the template location the field originates from
        def key
          @run[FIELD_KEY]
        end

        # true if the placeholder is the only content of the cell
        def whole_cell?
          @cell[WHOLE_CELL_MARKER] == '1'
        end

        def row
          @cell.parent
        end

        def start_node
          @cell
        end
        alias end_node start_node

        # Inserts a value. Numbers, dates, times and booleans are stored as
        # native cell values and nil results in a blank cell when the field
        # is the only content of the cell. Otherwise the text representation
        # of the value is inserted.
        def replace_value(value, env)
          if whole_cell? && !value.is_a?(Sablon::Content)
            return remove if value.nil?
            native = Sablon::Spreadsheet::CellValue.native(value, Sablon::Spreadsheet.date1904?(env))
            return write_native(native) if native
          end
          return remove unless value
          replace(Sablon::Content.wrap(value), env)
        end

        # Inserts content into the run of the field, only text content can
        # be inserted into spreadsheets.
        def replace(content, _env)
          unless content.is_a?(Sablon::Content::String)
            raise ContextError, "Spreadsheets only support inserting text and values, " \
                                "#{content.class} can not be inserted into «#{expression}»"
          end
          text_node = @run.element_children.detect { |node| node.name == 't' }
          text = Sablon::Spreadsheet::CellValue.escape_text(content.string)
          text_node.content = text
          text_node['xml:space'] = 'preserve' if text =~ /\A\s|\s\z|\n/
          @run.remove_attribute(FIELD_MARKER)
          @run.remove_attribute(FIELD_KEY)
        end

        # removes only the placeholder
        def remove
          remove_or_decrement_ref(@run)
        end

        # removes the entire row or cell containing the field
        def remove_parent(type)
          remove_or_decrement_ref(type == :row ? row : @cell)
        end

        private

        def write_native(native)
          Sablon::Spreadsheet::CellValue.write_native(@cell, *native)
          @cell.remove_attribute(CELL_MARKER)
          @cell.remove_attribute(WHOLE_CELL_MARKER)
        end

        # removes the node if the reference count is less than or equal to 1
        def remove_or_decrement_ref(node)
          if @block_reference_count > 1
            @block_reference_count -= 1
          else
            node.remove
          end
        end
      end

      # Converts the string cells containing placeholders of the given rows
      # into inline strings where each placeholder is isolated in a run. The
      # block is called with each converted cell and returns the template
      # [row, column] of it. Returns the converted cells.
      def prepare_cells(rows, shared_strings)
        rows.each_with_object([]) do |row, cells|
          row.element_children.each do |cell|
            next unless cell.name == 'c'
            source = string_source(cell, shared_strings)
            next unless source
            pieces = split(source)
            next unless pieces
            rebuild(cell, pieces, yield(cell))
            cells << cell
          end
        end
      end

      # Returns the fields of the prepared cells within the node in
      # document order.
      def parse_fields(node)
        node.xpath(".//*[@#{FIELD_MARKER}]").map do |run|
          CellField.new(run.parent.parent, run)
        end
      end

      private

      # Returns the <si> or <is> node holding the text of a string cell
      def string_source(cell, shared_strings)
        return if cell.element_children.any? { |node| node.name == 'f' }
        case cell['t']
        when 's'
          value = cell.element_children.detect { |node| node.name == 'v' }
          shared_strings[value.text.to_i] if value && shared_strings
        when 'inlineStr'
          cell.element_children.detect { |node| node.name == 'is' }
        end
      end

      # Splits the rich text of a string into pieces of [run properties,
      # text, expression] where the expression is set for placeholders.
      # Returns nil if the text contains no placeholders.
      def split(source)
        runs = text_runs(source)
        text = runs.map(&:last).join
        return unless text =~ PLACEHOLDER
        #
        pieces = []
        pos = 0
        text.to_enum(:scan, PLACEHOLDER).each do
          match = Regexp.last_match
          pieces.concat(plain_pieces(runs, text, pos, match.begin(0)))
          pieces << [properties_at(runs, match.begin(0)), match[0], match[1]]
          pos = match.end(0)
        end
        pieces.concat(plain_pieces(runs, text, pos, text.length))
        [pieces, text =~ WHOLE_CELL ? true : false]
      end

      # Returns [run properties, text] pairs for all runs of a string
      def text_runs(source)
        runs = source.element_children.select { |node| node.name == 'r' }
        if runs.empty?
          text = source.element_children.detect { |node| node.name == 't' }
          return [[nil, text ? text.text : '']]
        end
        runs.map do |run|
          props = run.element_children.detect { |node| node.name == 'rPr' }
          text = run.element_children.detect { |node| node.name == 't' }
          [props, text ? text.text : '']
        end
      end

      # Text between placeholders split by the original runs so the
      # formatting is retained.
      def plain_pieces(runs, text, from, to)
        pieces = []
        offset = 0
        runs.each do |props, run_text|
          start = [from, offset].max
          stop = [to, offset + run_text.length].min
          pieces << [props, text[start...stop], nil] if stop > start
          offset += run_text.length
        end
        pieces
      end

      # Run properties of the run containing the character offset
      def properties_at(runs, pos)
        offset = 0
        runs.each do |props, run_text|
          offset += run_text.length
          return props if pos < offset
        end
        runs.last.first
      end

      def rebuild(cell, split_result, origin)
        pieces, whole = split_result
        cell.element_children.each do |node|
          node.remove if %w[v is].include?(node.name)
        end
        cell['t'] = 'inlineStr'
        inline = Nokogiri::XML::Node.new('is', cell.document)
        field_index = 0
        pieces.each do |props, text, expression|
          run = Sablon::Spreadsheet::CellValue.add_element(inline, 'r')
          run.add_child(props.dup) if props
          Sablon::Spreadsheet::CellValue.text_element(run, text)
          next unless expression
          run[FIELD_MARKER] = expression
          run[FIELD_KEY] = "#{origin.join(':')}:#{field_index}"
          field_index += 1
        end
        ext = cell.element_children.detect { |node| node.name == 'extLst' }
        ext ? ext.add_previous_sibling(inline) : cell.add_child(inline)
        cell[CELL_MARKER] = '1'
        cell[WHOLE_CELL_MARKER] = '1' if whole
      end
    end
  end
end
