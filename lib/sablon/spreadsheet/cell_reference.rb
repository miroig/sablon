module Sablon
  module Spreadsheet
    # Conversion helpers for A1 style cell references
    module CellReference
      MAX_ROWS = 1_048_576
      MAX_COLUMNS = 16_384
      PATTERN = /\A(\$?)([A-Za-z]{1,3})(\$?)(\d+)\z/

      module_function

      # Converts column letters to a 1 based index, i.e. "A" => 1, "AA" => 27
      def column_index(letters)
        letters.upcase.each_char.inject(0) { |sum, char| sum * 26 + char.ord - 64 }
      end

      # Converts a 1 based column index to letters, i.e. 28 => "AB"
      def column_letters(index)
        letters = +''
        while index > 0
          index, remainder = (index - 1).divmod(26)
          letters.prepend((65 + remainder).chr)
        end
        letters
      end

      # Returns [row, column] for a reference like "B12" or "$B$12" and nil
      # if the text is not a valid cell reference.
      def parse(reference)
        match = PATTERN.match(reference.to_s)
        return unless match
        row = match[4].to_i
        col = column_index(match[2])
        [row, col] if valid?(row, col)
      end

      def format(row, col, abs_row = false, abs_col = false)
        "#{'$' if abs_col}#{column_letters(col)}#{'$' if abs_row}#{row}"
      end

      def valid?(row, col)
        valid_row?(row) && valid_column?(col)
      end

      def valid_row?(row)
        row >= 1 && row <= MAX_ROWS
      end

      def valid_column?(col)
        col >= 1 && col <= MAX_COLUMNS
      end
    end
  end
end
