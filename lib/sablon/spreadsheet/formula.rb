require 'strscan'
require 'sablon/spreadsheet/cell_reference'

module Sablon
  module Spreadsheet
    # Finds and rewrites cell references in the A1 style formula text used by
    # SpreadsheetML documents. Values inside string literals, structured table
    # references, function names and defined names are never touched.
    module Formula
      # A reference located in formula text.
      #
      # +scope+ is :local for unqualified references, :sheet for references
      # qualified by a single sheet name and :external for 3D references and
      # references into other workbooks.
      # +kind+ is :cell, :range, :rows (i.e. 1:3) or :columns (i.e. A:C), the
      # coordinates not used by the kind of reference are nil.
      # +start+ and +stop+ are the character offsets of the reference text
      # excluding any sheet qualifier.
      class Reference
        attr_accessor :scope, :sheet, :kind, :start, :stop,
                      :row1, :col1, :row2, :col2,
                      :abs_row1, :abs_col1, :abs_row2, :abs_col2

        def initialize(attrs = {})
          attrs.each { |key, value| public_send("#{key}=", value) }
        end

        def range?
          kind != :cell
        end

        # Returns the reference text with the relative parts shifted by the
        # given offsets or "#REF!" if the result is outside of the sheet.
        def translate(drow, dcol)
          copy = dup
          copy.row1 += drow if row1 && !abs_row1
          copy.row2 += drow if row2 && !abs_row2
          copy.col1 += dcol if col1 && !abs_col1
          copy.col2 += dcol if col2 && !abs_col2
          copy.valid? ? copy.to_s : REF_ERROR
        end

        def valid?
          [row1, row2].compact.all? { |r| CellReference.valid_row?(r) } &&
            [col1, col2].compact.all? { |c| CellReference.valid_column?(c) }
        end

        def to_s
          case kind
          when :cell
            CellReference.format(row1, col1, abs_row1, abs_col1)
          when :range
            CellReference.format(row1, col1, abs_row1, abs_col1) + ':' +
              CellReference.format(row2, col2, abs_row2, abs_col2)
          when :rows
            "#{'$' if abs_row1}#{row1}:#{'$' if abs_row2}#{row2}"
          when :columns
            "#{'$' if abs_col1}#{CellReference.column_letters(col1)}:" \
              "#{'$' if abs_col2}#{CellReference.column_letters(col2)}"
          end
        end
      end

      REF_ERROR = '#REF!'.freeze
      BOUNDARY = /(?![\p{L}\p{N}_.\\(\[!'])/
      STRING = /"(?:[^"]|"")*"?/
      QUOTED_SHEET = /'((?:[^']|'')*)'!/
      SHEET = /([\p{L}_\\][\p{L}\p{N}_.\\]*)(:[\p{L}_\\][\p{L}\p{N}_.\\]*)?!/
      ERROR = %r{#[A-Za-z0-9/_]+[!?]?}
      CELL_RANGE = /(\$?)([A-Za-z]{1,3})(\$?)(\d+)(?::(\$?)([A-Za-z]{1,3})(\$?)(\d+))?#{BOUNDARY}/
      COLUMNS = /(\$?)([A-Za-z]{1,3}):(\$?)([A-Za-z]{1,3})#{BOUNDARY}/
      ROWS = /(\$?)(\d+):(\$?)(\d+)#{BOUNDARY}/
      NUMBER = /\d+(?:\.\d*)?(?:[eE][+-]?\d+)?/
      IDENTIFIER = /[\p{L}\p{N}_.\\?]+/

      module_function

      # Returns all cell references found in the formula text
      def references(text)
        Scanner.new(text.to_s).references
      end

      # Replaces each reference with the string returned by the block. The
      # reference is left as is when the block returns nil.
      def rewrite(text)
        text = text.to_s
        refs = references(text)
        return text if refs.empty?
        #
        result = +''
        last = 0
        refs.each do |ref|
          replacement = yield(ref)
          next if replacement.nil?
          result << text[last...ref.start] << replacement
          last = ref.stop
        end
        result << text[last..-1]
      end

      # Moves the relative references of a formula by the given offsets, the
      # same way spreadsheet applications do when a formula is copied.
      def translate(text, drow, dcol)
        return text if drow.zero? && dcol.zero?
        rewrite(text) { |ref| ref.translate(drow, dcol) }
      end

      # Splits a "sqref" attribute value (space separated list of cells
      # and ranges) and rewrites each item with the given block.
      def rewrite_sqref(text)
        items = text.to_s.split(/\s+/).reject(&:empty?).map do |item|
          ref = references(item).first
          next item unless ref && ref.start.zero? && ref.stop == item.length
          yield(ref) || item
        end
        items.reject { |item| item == REF_ERROR }.join(' ')
      end

      # Tokenizer used to locate references
      class Scanner
        def initialize(text)
          @text = text
          @ss = StringScanner.new(text)
          @refs = []
        end

        def references
          scan_token until @ss.eos?
          @refs
        end

        private

        def scan_token
          char = @ss.check(/./m)
          if char == '"'
            @ss.scan(STRING)
          elsif char == "'"
            scan_quoted_sheet
          elsif char == '['
            scan_brackets
            scan_external_qualifier
          elsif char == '#'
            @ss.getch unless @ss.scan(ERROR)
          elsif char =~ /[\p{L}\p{N}_\\$]/
            scan_word
          else
            @ss.getch
          end
        end

        def scan_quoted_sheet
          if @ss.scan(QUOTED_SHEET)
            name = @ss[1].gsub("''", "'")
            external = name.include?('[') || name.include?(':')
            scan_reference(external ? :external : :sheet, name)
          else
            @ss.getch
          end
        end

        # Consumes a bracket group like "[1]" or "Table1[[#Headers],[Col]]"
        # taking escape characters (') inside of it into account.
        def scan_brackets
          depth = 0
          until @ss.eos?
            char = @ss.getch
            if char == "'"
              @ss.getch
            elsif char == '['
              depth += 1
            elsif char == ']'
              depth -= 1
              break if depth.zero?
            end
          end
        end

        # External workbook references look like: [1]Sheet1!A1
        def scan_external_qualifier
          scan_reference(:external, @ss[1]) if @ss.scan(SHEET)
        end

        def scan_word
          if @ss.check(/[\p{L}_\\]/) && @ss.scan(SHEET)
            scope = @ss[2] ? :external : :sheet
            scan_reference(scope, @ss[1])
          elsif !scan_reference(:local, nil)
            if @ss.check(/\d/)
              @ss.scan(NUMBER)
            else
              @ss.scan(IDENTIFIER) || @ss.getch
            end
          end
        end

        # Attempts to read a reference at the current position. Returns true
        # if a reference was found.
        def scan_reference(scope, sheet)
          start = @ss.charpos
          ref = scan_cell_range || scan_columns || scan_rows
          return false unless ref
          ref.scope = scope
          ref.sheet = sheet
          ref.start = start
          ref.stop = @ss.charpos
          @refs << ref
          true
        end

        def scan_cell_range
          pos = @ss.pos
          return unless @ss.scan(CELL_RANGE)
          ref = Reference.new(kind: @ss[5] ? :range : :cell,
                              abs_col1: !@ss[1].empty?,
                              col1: CellReference.column_index(@ss[2]),
                              abs_row1: !@ss[3].empty?,
                              row1: @ss[4].to_i)
          if @ss[5]
            ref.abs_col2 = !@ss[5].empty?
            ref.col2 = CellReference.column_index(@ss[6])
            ref.abs_row2 = !@ss[7].empty?
            ref.row2 = @ss[8].to_i
          end
          valid_or_rewind(ref, pos)
        end

        def scan_columns
          pos = @ss.pos
          return unless @ss.scan(COLUMNS)
          ref = Reference.new(kind: :columns,
                              abs_col1: !@ss[1].empty?,
                              col1: CellReference.column_index(@ss[2]),
                              abs_col2: !@ss[3].empty?,
                              col2: CellReference.column_index(@ss[4]))
          valid_or_rewind(ref, pos)
        end

        def scan_rows
          pos = @ss.pos
          return unless @ss.scan(ROWS)
          ref = Reference.new(kind: :rows,
                              abs_row1: !@ss[1].empty?, row1: @ss[2].to_i,
                              abs_row2: !@ss[3].empty?, row2: @ss[4].to_i)
          valid_or_rewind(ref, pos)
        end

        def valid_or_rewind(ref, pos)
          return ref if ref.valid?
          @ss.pos = pos
          nil
        end
      end
    end
  end
end
