GC.disable

class NanoVMException < NameError
   attr_reader :function
   def initialize msg, function
      @function = function
      super(msg)
   end
end

class Context
   attr_accessor :data_inspector
   attr_accessor :builder_function
   attr_accessor :my_callback
   attr_accessor :make_comment
end

