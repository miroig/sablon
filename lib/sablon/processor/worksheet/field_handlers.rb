module Sablon
  module Processor
    class Worksheet
      # Handles value insertion into cells. Unlike text insertion in Word
      # documents, numbers, dates, times and booleans are stored as native
      # cell values when the field is the only content of a cell.
      class InsertionHandler < Processor::Document::FieldHandler
        def initialize
          super(/^=/)
        end

        def build_statement(_constructor, field, options = {})
          return unless options[:allow_insertion]
          #
          expr = Expression.parse(field.expression.gsub(/^=/, ''))
          Statement::CellInsertion.new(expr, field)
        end
      end
    end
  end
end
