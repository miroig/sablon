require 'sablon/document_object_model/file_handler'

module Sablon
  module DOM
    # Wraps the workbook part of a spreadsheet (xl/workbook.xml)
    class Workbook < FileHandler
      ENTRY_NAME = 'xl/workbook.xml'.freeze
      # elements that precede calcPr in the workbook according to the schema
      BEFORE_CALC_PR = %w[fileVersion fileSharing workbookPr workbookProtection
                          bookViews sheets functionGroups externalReferences
                          definedNames].freeze
      Sheet = Struct.new(:name, :rid)

      #
      # extends the Model class so it now has a "spreadsheet" method which
      # coordinates the processing of the parts of a spreadsheet.
      def self.extend_model(model_klass)
        super do
          define_method(:spreadsheet) do
            @spreadsheet ||= Sablon::Spreadsheet::Package.new(self)
          end
        end
      end

      def initialize(xml_node)
        super
        @xml = xml_node
        @root = xml_node.root
      end

      def sheets
        @root.xpath('./*[local-name() = "sheets"]/*[local-name() = "sheet"]').map do |node|
          rid = node.attributes.values.detect { |attr| attr.name == 'id' }
          Sheet.new(node['name'], rid && rid.value)
        end
      end

      def date1904?
        pr = @root.at_xpath('./*[local-name() = "workbookPr"]')
        pr && %w[1 true].include?(pr['date1904'])
      end

      def defined_names
        @root.xpath('./*[local-name() = "definedNames"]/*[local-name() = "definedName"]')
      end

      # Forces spreadsheet applications to recalculate all formulas when
      # the workbook is opened.
      def full_calc_on_load!
        calc_pr = @root.at_xpath('./*[local-name() = "calcPr"]')
        unless calc_pr
          calc_pr = Nokogiri::XML::Node.new('calcPr', @xml)
          predecessor = @root.element_children.reverse.detect do |node|
            BEFORE_CALC_PR.include?(node.name)
          end
          predecessor ? predecessor.add_next_sibling(calc_pr) : @root.prepend_child(calc_pr)
        end
        calc_pr['fullCalcOnLoad'] = '1'
      end
    end

    # Wraps the shared strings part of a spreadsheet
    class SharedStrings < FileHandler
      # no model extensions are needed for shared strings
      def self.extend_model(_model_klass); end

      def initialize(xml_node)
        super
        @root = xml_node.root
        @items = @root ? @root.element_children.select { |node| node.name == 'si' } : []
      end

      # Returns the <si> node with the given index
      def [](index)
        @items[index]
      end

      # Updates the optional count of shared string references
      def adjust_count(delta)
        return unless @root && @root['count']
        @root['count'] = [@root['count'].to_i + delta, 0].max.to_s
      end
    end
  end
end
