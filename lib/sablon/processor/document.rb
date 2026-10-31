require 'sablon/processor/field_handler_registry'
require 'sablon/processor/document/blocks'
require 'sablon/processor/document/field_handlers'
require 'sablon/processor/document/operation_construction'

module Sablon
  module Processor
    # This class manages processing of the XML portions of a word document
    # that can contain mailmerge fields
    class Document
      extend FieldHandlerRegistry

      def self.process(xml_node, env)
        processor = new(parser)
        processor.manipulate xml_node, env
      end

      def self.parser
        @parser ||= Sablon::Parser::MailMerge.new
      end

      def initialize(parser)
        @parser = parser
      end

      def manipulate(xml_node, env)
        operations = build_operations(@parser.parse_fields(xml_node))
        operations.each do |step|
          step.evaluate env
        end
        cleanup(xml_node)
        xml_node
      end

      private

      def build_operations(fields)
        OperationConstruction.new(fields,
                                  self.class.field_handlers.values,
                                  self.class.default_field_handler).operations
      end

      def cleanup(xml_node)
        fill_empty_table_cells xml_node
      end

      def fill_empty_table_cells(xml_node)
        selector = "//w:tc[count(*[name() = 'w:p'])=0 or not(*)]"
        xml_node.xpath(selector).each do |blank_cell|
          filler = Nokogiri::XML::Node.new('w:p', xml_node.document)
          blank_cell.add_child filler
        end
      end

      # register "builtin" handlers
      register_field_handler :insertion, InsertionHandler.new
      register_field_handler :each_loop, EachLoopHandler.new
      register_field_handler :conditional, ConditionalHandler.new
      register_field_handler :image, ImageHandler.new
      register_field_handler :comment, CommentHandler.new
    end
  end
end
