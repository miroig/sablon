require 'date'

module Sablon
  module Spreadsheet
    # Converts Ruby values into the representation stored in SpreadsheetML
    # cells and writes them into cell nodes.
    module CellValue
      EPOCH_1900 = Date.new(1899, 12, 30)
      EPOCH_1904 = Date.new(1904, 1, 1)
      FIRST_1900_DATE = Date.new(1900, 1, 1)
      # Excel treats 1900 as a leap year, serials before March 1900 are
      # shifted by one day because of the non existent 29th of February.
      LEAP_BUG_DATE = Date.new(1900, 3, 1)

      module_function

      # Returns the [type, value] pair used to store the value natively in
      # a cell. Returns nil if the value has no native representation.
      def native(value, date1904 = false)
        case value
        when true, false
          ['b', value ? '1' : '0']
        when Numeric
          text = number(value)
          ['n', text] if text
        when Time, Date
          serial = date_serial(value, date1904)
          ['n', number(serial)] if serial
        end
      end

      def number(value)
        case value
        when Integer
          value.to_s
        when Float
          value.to_s if value.finite?
        when Rational
          number(value.to_f)
        else
          if defined?(::BigDecimal) && value.is_a?(::BigDecimal)
            value.to_s('F') if value.finite?
          else
            float = (Float(value) rescue nil)
            number(float) if float
          end
        end
      end

      # Converts dates and times into serial date values, times are stored
      # as the fraction of the day using the local wall clock time. Returns
      # nil for dates that can't be represented by the date system.
      def date_serial(value, date1904 = false)
        date = Date.new(value.year, value.month, value.day)
        if date1904
          days = (date - EPOCH_1904).to_i
          return if days < 0
        else
          return if date < FIRST_1900_DATE
          days = (date - EPOCH_1900).to_i
          days -= 1 if date < LEAP_BUG_DATE
        end
        fraction = day_fraction(value)
        fraction.zero? ? days : days + fraction
      end

      def day_fraction(value)
        return 0 unless value.is_a?(Time) || value.is_a?(DateTime)
        subsec = value.is_a?(Time) ? value.subsec : value.sec_fraction
        Rational(value.hour * 3600 + value.min * 60 + value.sec, 86_400) + subsec / 86_400
      end

      # Escapes text for use in a cell. Literal text matching the "_xHHHH_"
      # escape format needs its leading underscore escaped and characters
      # that are not allowed in XML are written using the escape format.
      def escape_text(text)
        text.gsub(/_(x[0-9A-Fa-f]{4}_)/) { "_x005F_#{Regexp.last_match(1)}" }
            .gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFE\uFFFF]/) { |char| format('_x%04X_', char.ord) }
      end

      # Replaces the content of the cell with a native value, keeping the
      # cell's style and other attributes.
      def write_native(cell, type, text)
        clear(cell)
        cell['t'] = type unless type == 'n'
        value = Nokogiri::XML::Node.new('v', cell.document)
        value.content = text
        ext = cell.element_children.detect { |child| child.name == 'extLst' }
        ext ? ext.add_previous_sibling(value) : cell.add_child(value)
      end

      # Turns the cell into a blank cell, keeping the style
      def clear(cell)
        cell.remove_attribute('t')
        cell.element_children.each do |child|
          child.remove unless child.name == 'extLst'
        end
      end

      def add_element(parent, name, text = nil)
        node = Nokogiri::XML::Node.new(name, parent.document)
        node.content = text if text
        parent.add_child(node)
        node
      end

      # Creates a text node for inline strings preserving whitespace
      def text_element(parent, text)
        node = add_element(parent, 't', text)
        node['xml:space'] = 'preserve' if text =~ /\A\s|\s\z|\n/
        node
      end
    end
  end
end
