module Sablon
  module Processor
    # Class level API used by processors to manage the field handlers that
    # turn template fields into statements. Each processor extending this
    # module keeps its own set of handlers.
    module FieldHandlerRegistry
      # Adds a new handler to the OperationConstruction class. The handler
      # passed in should be an instance of the Handler class or implement
      # the same interface. Handlers cannot be replaced by this method,
      # instead the `replace_field_handler` method should be used which
      # internally removes the existing handler and registers the one passed
      # in. The name 'default' is special and will be called if no other
      # handlers can use the provided field.
      def register_field_handler(name, handler)
        name = name.to_sym
        if field_handlers[name] || (name == :default && !default_field_handler.nil?)
          msg = "Handler named: '#{name}' already exists. Use `replace_field_handler` instead."
          raise ArgumentError, msg
        end
        #
        if name == :default
          @default_field_handler = handler
        else
          field_handlers[name] = handler
        end
      end

      # Removes a handler from the hash and returns it
      def remove_field_handler(name)
        name = name.to_sym
        if name == :default
          handler = @default_field_handler
          @default_field_handler = nil
          handler
        else
          field_handlers.delete(name)
        end
      end

      # Replaces an existing handler
      def replace_field_handler(name, handler)
        remove_field_handler(name)
        register_field_handler(name, handler)
      end

      def field_handlers
        @field_handlers ||= {}
      end

      def default_field_handler
        @default_field_handler ||= nil
      end
    end
  end
end
