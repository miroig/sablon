require 'sablon/document_object_model/model'
require 'sablon/parser/worksheet'
require 'sablon/spreadsheet/cell_reference'
require 'sablon/spreadsheet/cell_value'
require 'sablon/spreadsheet/formula'
require 'sablon/spreadsheet/position_map'
require 'sablon/spreadsheet/layout'
require 'sablon/spreadsheet/reference_updater'
require 'sablon/spreadsheet/package'

module Sablon
  # Classes used to render spreadsheet (xlsx) templates
  module Spreadsheet
    # Returns true if the template being rendered uses the 1904 date system
    def self.date1904?(env)
      template = env && env.template
      document = template && template.document
      document.respond_to?(:spreadsheet) ? document.spreadsheet.date1904? : false
    end
  end
end
