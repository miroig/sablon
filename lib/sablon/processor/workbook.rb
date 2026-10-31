require 'sablon/spreadsheet'

module Sablon
  module Processor
    # Prepares the workbook of a spreadsheet template. Preparation happens
    # once per rendering, either here or when the first worksheet is
    # processed, whichever comes first.
    class Workbook
      def self.process(_xml_node, env)
        env.document.spreadsheet.prepare!
      end
    end
  end
end
