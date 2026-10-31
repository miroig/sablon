module Sablon
  # Combines the user supplied context and template into a single object
  # to manage data during template processing.
  class Environment
    attr_reader :template
    attr_reader :context
    attr_reader :section_properties

    # returns a new environment with merged contexts. Only the new values
    # need to be transformed because the existing context already is, this
    # keeps loops over large collections fast.
    def alter_context(context = {})
      new_context = @context.merge(Context.transform_hash(context))
      Environment.new(template, new_context, false)
    end

    # reader method for the DOM::Model instance stored on the template
    def document
      @template.document
    end

    def section_properties=(properties)
      @section_properties = Context.transform_hash(properties)
    end

    private

    def initialize(template, context = {}, transform = true)
      @template = template
      @context = transform ? Context.transform_hash(context) : context
    end
  end
end
