module Sablon
  module Processor
    class Worksheet
      # The rows or cells enclosed by a start and an end field. Fields in
      # different rows enclose the rows between them, fields in the same row
      # enclose the cells between them.
      class Block
        attr_accessor :start_field, :end_field

        def self.enclosed_by(start_field, end_field)
          if start_field.cell == end_field.cell
            raise TemplateError, "«#{start_field.expression}» and «#{end_field.expression}» " \
                                 'need to be in different cells. Blocks within a single cell ' \
                                 'are not supported in spreadsheets.'
          end
          #
          block_class = start_field.row == end_field.row ? CellRangeBlock : RowBlock
          block_class.new(start_field, end_field)
        end

        def initialize(start_field, end_field)
          @start_field = start_field
          @end_field = end_field
          @iterations = 0

          # update reference counts for control fields
          @start_field.block_reference_count += 1
          @end_field.block_reference_count += 1
        end

        # Renders a copy of the enclosed rows or cells. The generated nodes
        # are stamped with the iteration so references between them can be
        # resolved later on.
        def process(env)
          doc = start_node.document
          container = Nokogiri::XML::Node.new('tmp', doc)
          container.children = Nokogiri::XML::NodeSet.new(doc, body.map(&:dup))
          Processor::Worksheet.process_nodes(container, env)
          #
          nodes = container.element_children.to_a
          copy = Spreadsheet::Layout.next_copy_id
          nodes.each { |node| Spreadsheet::Layout.stamp(node, start_field.key, copy, @iterations) }
          @iterations += 1
          nodes
        end

        def replace(content)
          content.each { |node| start_node.add_next_sibling(node) }
          remove_control_elements
        end

        def remove_control_elements
          body.each(&:remove)
          start_field.remove_parent(self.class.parent_type)
          end_field.remove_parent(self.class.parent_type)
        end

        def body
          return @body if defined?(@body)
          @body = []
          node = start_node
          while (node = node.next_element) && node != end_node
            @body << node
          end
          @body
        end
      end

      # Repeats or removes the rows between the rows of the fields, the rows
      # containing the fields are removed.
      class RowBlock < Block
        def self.parent_type
          :row
        end

        def start_node
          @start_node ||= start_field.row
        end

        def end_node
          @end_node ||= end_field.row
        end
      end

      # Repeats or removes the cells between the cells of the fields within
      # a row, the cells containing the fields are removed and the
      # remaining cells of the row are moved accordingly.
      class CellRangeBlock < Block
        def self.parent_type
          :cell
        end

        def start_node
          start_field.cell
        end

        def end_node
          end_field.cell
        end
      end
    end
  end
end
