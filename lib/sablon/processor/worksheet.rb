require 'sablon/spreadsheet'
require 'sablon/processor/document'
require 'sablon/processor/field_handler_registry'
require 'sablon/processor/worksheet/blocks'
require 'sablon/processor/worksheet/field_handlers'

module Sablon
  module Processor
    # Renders the worksheets of a spreadsheet template. Worksheets use
    # "{{...}}" placeholders typed into cells instead of MailMerge fields,
    # the expressions inside of the placeholders are the same as in Word
    # documents.
    class Worksheet
      extend FieldHandlerRegistry

      class << self
        def process(xml_node, env)
          new(parser).render(xml_node, env)
        end

        # Processes the fields within the copied content of a block
        def process_nodes(node, env)
          new(parser).manipulate(node, env)
        end

        def parser
          @parser ||= Sablon::Parser::Worksheet.new
        end
      end

      def initialize(parser)
        @parser = parser
      end

      def render(doc, env)
        model = env.document
        package = model.spreadsheet
        package.prepare!
        sheet_data = doc.at_xpath('/*/*[local-name() = "sheetData"]')
        return doc unless sheet_data
        #
        shared_strings = package.shared_strings
        shared_count = count_shared_strings(sheet_data)
        layout = Spreadsheet::Layout.new(sheet_data)
        layout.prepare(@parser, shared_strings)
        return doc unless layout.changes?
        #
        manipulate(sheet_data, env)
        package.keep_table_rows(model.current_entry, layout)
        map = layout.finalize
        updater = Spreadsheet::ReferenceUpdater.new(map, package.sheet_name(model.current_entry))
        updater.update_cell_formulas(sheet_data, layout)
        updater.update_sheet_ranges(doc)
        update_dimension(doc, layout.cleanup)
        shared_strings.adjust_count(count_shared_strings(sheet_data) - shared_count) if shared_strings
        package.update_references(model.current_entry, map)
        doc
      end

      def manipulate(node, env)
        operations = build_operations(@parser.parse_fields(node))
        operations.each do |step|
          step.evaluate env
        end
        node
      end

      private

      def build_operations(fields)
        Document::OperationConstruction.new(fields,
                                            self.class.field_handlers.values,
                                            self.class.default_field_handler,
                                            Block).operations
      end

      def count_shared_strings(sheet_data)
        sheet_data.xpath('count(./*/*[@t = "s"])').to_i
      end

      def update_dimension(doc, box)
        dimension = doc.at_xpath('/*/*[local-name() = "dimension"]')
        return unless dimension
        dimension['ref'] = if box.nil?
                             'A1'
                           elsif box[0] == box[2] && box[1] == box[3]
                             Spreadsheet::CellReference.format(box[0], box[1])
                           else
                             Spreadsheet::CellReference.format(box[0], box[1]) + ':' +
                               Spreadsheet::CellReference.format(box[2], box[3])
                           end
      end

      # register "builtin" handlers
      register_field_handler :insertion, InsertionHandler.new
      register_field_handler :each_loop, Document::EachLoopHandler.new
      register_field_handler :conditional, Document::ConditionalHandler.new
    end
  end
end
