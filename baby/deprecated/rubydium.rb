require "test/unit"
require 'libjit'
include LibJit
require './ast_crawler.rb'
# new ast crawling mechanisms
# debug helpers
def gb statement
   p statement.methods - Object.instance_methods - Enumerable.instance_methods
end
def print_num f, num
   numv = Value.new
   f.fill_value_with_constant numv, :int, num
   f.insn_call_print_int numv
end
$functions = {}
$funcs = {}
def new_method type_sym, method_name
   [$types[type_sym], $func2id[method_name]]
end
$func2id = {
   "__SELF__.set_element" => 0,
   "__SELF__.get_element" => 1,
   "__SELF__.realloc"     => 2,
   "__SELF__.alloc"       => 3
}
$top_id = $func2id.length
# TODO - split up boolean into TrueClass and FalseClass
$types = { :VBoolean   => 1, 
           :VInteger   => 2, 
           :VType      => 3,
           :VNil       => 4,
           :VByteArray => 5,
           :VGlobal    => 6
        }
$funcparams = {
   new_method(:VByteArray, "__SELF__.set_element") => ["self", "pos", "val"],
   new_method(:VByteArray, "__SELF__.get_element") => ["self", "pos"],
   new_method(:VByteArray, "__SELF__.realloc")     => ["self", "size"],
   new_method(:VByteArray, "__SELF__.alloc")       => ["self", "size"]
}
def new_type_id constant
   $types[constant] = $types.length
end
class BlubContext
   attr_accessor :vars, :module_stack, :build_function_type_id_stack
   def initialize
      @vars = {}
      @module_stack = []
      @build_function_type_id_stack = []
   end
end
class TypedValue
   attr_accessor :function, :address, :jit_var
   def TypedValue.wrap_existing_value f, val
      v = TypedValue.new
      v.jit_var = val
      v.function = f
      v.address = nil
      v
   end
   def TypedValue.new_typed_value f
      v = TypedValue.new
      v.jit_var = Value.new
      v.function = f
      v.address = nil
      v.function.create_local v.jit_var, :rmval
      v
   end
   def TypedValue.wrap_existing_address f, addr
      v = TypedValue.new
      v.jit_var  = nil
      v.function = f
      v.address  = addr
      v
   end
   def address
      if @address.nil?
         @address = Value.new
         @function.insn_address_of @address, @jit_var
      end
      @address
   end
   def store_type t
      @function.insn_store_relative address, $context.get_struct_offset(:rmval, 0), t
   end
   def store_value v
      @function.insn_store_relative address, $context.get_struct_offset(:rmval, 1), v
   end
   def type
      t = Value.new
      @function.insn_load_relative t, address, $context.get_struct_offset(:rmval, 0), :int
      t
   end
   def value
      v = Value.new
      @function.insn_load_relative v, address, $context.get_struct_offset(:rmval, 1), :int
      v
   end
end
def my_build_function type_id, the_id
   f = $functions[[type_id, the_id]]
   return f unless f.nil?
   method_name = $func2id.index the_id
   prototype = nil
   id_arr = [type_id, the_id]
   block = $funcs[id_arr]
   prototype = [:int] * ($funcparams[id_arr].size * 2)
   param_list = $funcparams[id_arr]
   f = Function.new $context
   puts "BUILDING FUNCTION #{method_name} [#{the_id}] : #{prototype} : FOR OBJECT OF TYPE #{$types.index type_id}"
   puts "BODY : #{block}"
   f.lock { 
      f.create_with_prototype :void_ptr, prototype
      bctx = BlubContext.new
      bctx.build_function_type_id_stack << type_id
      param_list.each_with_index {
         |blub, idx|
         raise "eek param matches var" if bctx.vars.has_key? blub
         # read in the subvalues
         type = Value.new
         f.fill_value_with_param type, (idx * 2) + 0
         actual = Value.new
         f.fill_value_with_param actual, (idx * 2) + 1
         # create typed value and fill in
         local = TypedValue.new_typed_value f
         local.store_type  type
         local.store_value actual
         # use this as a local variable
         bctx.vars[blub] = local.jit_var
      }
      case method_name
      when "__SELF__.get_element"
         temp = Value.new
         arr = TypedValue.wrap_existing_value f, bctx.vars["self"]
         pos_tv = TypedValue.wrap_existing_value f, bctx.vars["pos"]
         f.insn_load_elem temp, arr.value, pos_tv.value, :int
         # create the type value
         type = Value.new
         f.fill_value_with_constant type, :int, $types[:VInteger]
         # create typed value and fill in
         struct = TypedValue.new_typed_value f
         struct.store_type  type
         struct.store_value temp
         retval = struct.jit_var
      when "__SELF__.realloc"
         arr = TypedValue.wrap_existing_value f, bctx.vars["self"]
         realloced_addr = Value.new
         size_tv = TypedValue.wrap_existing_value f, bctx.vars["size"]
         f.insn_call_realloc_bytearray realloced_addr, arr.value, size_tv.value
         arr.store_value realloced_addr
      when "__SELF__.alloc"
         alloced_addr = Value.new
         size_tv = TypedValue.wrap_existing_value f, bctx.vars["size"]
         # f.insn_call_alloc_bytearray alloced_addr, size_tv.value
         # arr = TypedValue.wrap_existing_value f, bctx.vars["self"]
         # arr.store_value alloced_addr
      when "__SELF__.set_element"
         arr = TypedValue.wrap_existing_value f, bctx.vars["self"]
         pos_tv = TypedValue.wrap_existing_value f, bctx.vars["pos"]
         val_tv = TypedValue.wrap_existing_value f, bctx.vars["val"]
         f.insn_store_elem arr.value, pos_tv.value, val_tv.value
         retval = nil
      else
         retval = gen_for_ast f, block, bctx
      end
      if retval.nil?
         # create the type value
         type = Value.new
         f.fill_value_with_constant type, :int, $types[:VNil]
         # create the actual value
         actual = Value.new
         f.fill_value_with_constant actual, :int, 0
         # create typed value and fill in
         struct = TypedValue.new_typed_value f
         struct.store_type  type
         struct.store_value actual
         retval = struct.jit_var
      end
      retval_tv = TypedValue.wrap_existing_value f, retval 
      ret = TypedValue.new_typed_value f
      ret.store_type  retval_tv.type
      ret.store_value retval_tv.value
      addr = Value.new
      f.insn_address_of addr, ret.jit_var
      f.insn_return addr
      f.compile
   }
   $functions[[type_id, the_id]] = f
   return f
end
def my_callback my_string
   puts "CALLBACK :: '#{my_string}'"
   $str_buffer << my_string
end
def gen_for_ast func, statement, bctx
   case statement
   when Ruby::AST::Literal::AtomicLiteral::FalseLiteral
      # create the type value
      type = Value.new
      func.fill_value_with_constant type, :int, $types[:VBoolean]
      # create the actual value
      actual = Value.new
      func.fill_value_with_constant actual, :int, 0
      # create typed value and fill in
      struct = TypedValue.new_typed_value func
      struct.store_type  type
      struct.store_value actual
      return struct.jit_var
   when Ruby::AST::Literal::AtomicLiteral::TrueLiteral
      # create the type value
      type = Value.new
      func.fill_value_with_constant type, :int, $types[:VBoolean]
      # create the actual value
      actual = Value.new
      func.fill_value_with_constant actual, :int, 1
      # create typed value and fill in
      struct = TypedValue.new_typed_value func
      struct.store_type  type
      struct.store_value actual
      return struct.jit_var
   when Ruby::AST::Literal::ValueLiteral::IntegerLiteral
      # create the type value
      type = Value.new
      func.fill_value_with_constant type, :int, $types[:VInteger]
      # create the actual value
      actual = Value.new
      func.fill_value_with_constant actual, :int, statement.to_a.first
      # create typed value and fill in
      struct = TypedValue.new_typed_value func
      struct.store_type  type
      struct.store_value actual
      return struct.jit_var
   when Ruby::AST::Literal::ValueLiteral::StringLiteral
      # create the type value
      type = Value.new
      func.fill_value_with_constant type, :int, $types[:VByteArray]
      # create the value value
      size = Value.new
      func.fill_value_with_constant size, :int, (statement.value.length + 1) * 4
      alloced_addr = Value.new
      func.insn_call_alloc_bytearray alloced_addr, size
      # store the length as the first element
      len_val = Value.new
      func.fill_value_with_constant len_val, :int, statement.value.length
      func.insn_store_relative alloced_addr, 0, len_val
      # store the string as the rest!
      addr_offs = 4
      statement.value.each_byte {
         |byte|
         byte_val = Value.new
         func.fill_value_with_constant byte_val, :int, byte
         func.insn_store_relative alloced_addr, addr_offs, byte_val
         addr_offs += 4
      }
      # create typed value and fill in
      struct = TypedValue.new_typed_value func
      struct.store_type  type
      struct.store_value alloced_addr
      return struct.jit_var
   when Ruby::AST::Assignment::GlobalAssign
      raise "global variables not yet support"
   when Ruby::AST::Assignment::LocalAssign
      dest, value = *statement.to_a
      temp = gen_for_ast func, value, bctx
      if !bctx.vars.has_key? dest
         var = Value.new 
         puts "creating new local #{var}"
         func.create_local var, :rmval
         bctx.vars[dest] = var
      end
      puts "assigning #{dest} with value #{temp}"
      temp_tv = TypedValue.wrap_existing_value func, temp
      var_tv = TypedValue.wrap_existing_value func, bctx.vars[dest]
      var_tv.store_type  temp_tv.type
      var_tv.store_value temp_tv.value
      return var_tv.jit_var
   when Ruby::AST::Klass
      puts "got a class : #{statement.name.inspect}"
      parent = statement.name
      # TODO - we actually need to take the parent.parent into account - guess this is the container module?
      new_type_id parent.constant
      bctx.module_stack.push parent
      gen_for_ast func, statement.body, bctx
      bctx.module_stack.pop
   when Ruby::AST::Scope
      gen_for_ast func, statement.statements, bctx
   when Ruby::AST::LocalVar
      return bctx.vars[statement.to_a.first]
   when Ruby::AST::Block
      ret = nil
      statement.each {
         |s|
         ret = gen_for_ast func, s, bctx
      }
      ret
   when Ruby::AST::Not
      inner = *statement.to_a
      value_struct = gen_for_ast func, inner, bctx
      value_struct_tv = TypedValue.wrap_existing_value func, value_struct 
      value = value_struct_tv.value
      temp = Value.new
      func.insn_to_not_bool temp, value
      # create the type value
      type = Value.new
      func.fill_value_with_constant type, :int, $types[:VBoolean]
      # create typed value and fill in
      struct = TypedValue.new_typed_value func
      struct.store_type  type
      struct.store_value temp
      return struct.jit_var
   when Ruby::AST::If
      expression, then_clause, else_clause = *statement.to_a
      end_of_then, end_of_else = Label.new, Label.new
      cond = gen_for_ast func, expression, bctx
      cond_tv = TypedValue.wrap_existing_value func, cond 
      func.insn_branch_if_not cond_tv.value, end_of_then
      gen_for_ast func, then_clause, bctx
      func.insn_branch end_of_else
      func.insn_label end_of_then
      if !else_clause.nil?
         gen_for_ast func, else_clause, bctx
         func.insn_label end_of_else
      end
   when Ruby::AST::While
      expression, body = *statement.to_a
      start_of_loop, finish_loop = Label.new, Label.new
      func.insn_label start_of_loop
      cond = gen_for_ast func, expression, bctx
      cond_tv = TypedValue.wrap_existing_value func, cond 
      func.insn_branch_if_not cond_tv.value, finish_loop
      gen_for_ast func, body, bctx
      func.insn_branch start_of_loop
      func.insn_label finish_loop
   when Ruby::AST::Iteration
      $iteration_body = statement.body # need to figure out how to handle multiple/nested iterations :>
      dyn_var_setter = statement.args  # |val| -> DynAssignCurrent[:val, nil]
      local_name = dyn_var_setter.name # are there other possibles? e.g, if it mirrors a local name is that used?
      yielder = statement.object
      puts "for #{local_name} in (#{yielder.method_name}) { #{$iteration_body.inspect} } - not passing yielder arguments!"
   when Ruby::AST::Defs
      method_name = "#{statement.reciever.variable_id}.#{statement.name}"
      type_id = $types[statement.reciever.variable_id]
      $func2id[method_name] = $top_id
      id_arr = [type_id, $top_id]
      $funcs[id_arr] = statement.defn
      $funcparams[id_arr] = [] # no params??
      $top_id += 1
   when Ruby::AST::GlobalVar
      raise "global variables not yet support"
   when Ruby::AST::Def
      method_name, params, body = *statement.to_a 
      puts "going to define method #{method_name.inspect} with module stack #{bctx.module_stack.inspect} (#{statement.inspect})"
      if bctx.module_stack.empty?
         puts "line, doing like global and stuff yay"
      else
         class_constant = bctx.module_stack.first.constant
         puts "shortcutting to defining method #{method_name.inspect} in class #{class_constant.inspect}"
         method_name = "__SELF__.#{method_name}"
         puts "defining method #{method_name}"
      end
      id = $func2id[method_name]
      if id.nil?
         $func2id[method_name] = $top_id
         id = $top_id
         $top_id += 1
      end
      class_constant = :VGlobal if class_constant.nil?
      id_arr = [$types[class_constant.to_sym], id]
      $funcs[id_arr] = body
      params = params.dup
      params.unshift :self unless class_constant == :VGlobal
      $funcparams[id_arr] = params
   when Ruby::AST::Return
      retval = gen_for_ast func, statement.mvalue, bctx
      retval_tv = TypedValue.wrap_existing_value func, retval 
      ret = TypedValue.new_typed_value func
      ret.store_type  retval_tv.type
      ret.store_value retval_tv.value
      addr = Value.new
      func.insn_address_of addr, ret.jit_var
      func.insn_return addr
      nil
   when Ruby::AST::Ivar
      self_type = Value.new
      func.fill_value_with_param self_type, 0
      self_addr = Value.new
      func.fill_value_with_param self_addr, 1

      type = Value.new
      func.fill_value_with_constant type, :int, $types[:VByteArray]
      # create the value value
      this = TypedValue.new_typed_value func
      this.store_type  type
      this.store_value self_addr
      bctx.vars[:this] = this.jit_var

      block = Ruby::AST::FunCall[:core_get_member, 
                                Ruby::AST::ArrayLiteral[[Ruby::AST::LocalVar[:this], 
                                                         Ruby::AST::IntegerLiteral[statement.attr_name.id]]]]
      struct = gen_for_ast func, block, bctx

      struct_tv = TypedValue.wrap_existing_value func, struct

      struct = TypedValue.new_typed_value func
      struct.store_type  struct_tv.type
      struct.store_value struct_tv.value
      return struct.jit_var
   when Ruby::AST::Iasgn
      self_type = Value.new
      func.fill_value_with_param self_type, 0
      # TODO - allow for changes to 'this' var
      self_addr = Value.new
      func.fill_value_with_param self_addr, 1

      value = statement.value
      attr_name = statement.attr_name
      lval_struct = gen_for_ast func, value, bctx
      bctx.vars[:value] = lval_struct

      type = Value.new
      func.fill_value_with_constant type, :int, $types[:VByteArray]
      # create the value value
      this = TypedValue.new_typed_value func
      this.store_type  type
      this.store_value self_addr
      bctx.vars[:this] = this.jit_var

      block = Ruby::AST::FunCall[:core_set_member, 
                                Ruby::AST::ArrayLiteral[[Ruby::AST::LocalVar[:this], 
                                                         Ruby::AST::IntegerLiteral[statement.attr_name.id],
                                                         Ruby::AST::LocalVar[:value]]]]
      struct = gen_for_ast func, block, bctx

      struct_tv = TypedValue.wrap_existing_value func, struct

      struct = TypedValue.new_typed_value func
      struct.store_type  struct_tv.type
      struct.store_value struct_tv.value
      return struct.jit_var
   when Ruby::AST::VCall, Ruby::AST::FunCall, Ruby::AST::Call
   if statement.is_a? Ruby::AST::Call and !statement.obj.is_a? Ruby::AST::Const
      src, call, param = *statement.to_a
      raise "sorry can't call a method on a variable thats not yet been set" if src.to_a.first.is_a? Value
      lval_struct = gen_for_ast func, src, bctx
      lval_struct_tv = TypedValue.wrap_existing_value func, lval_struct
      lval = lval_struct_tv.value
      if !param.to_a.first.nil?
         rval_struct = gen_for_ast func, param.to_a.first, bctx
         rval_struct_tv = TypedValue.wrap_existing_value func, rval_struct
         rval = rval_struct_tv.value
         puts "{lval}<#{lval.class}>.#{call}(#{rval}<#{rval.class}>)"
      else
         puts "{lval}<#{lval.class}>.#{call}()"
      end
      def do_builtin_math func, &block
         # create the type value
         type = Value.new
         func.fill_value_with_constant type, :int, $types[:VInteger]
         # create the actual value
         actual = Value.new
         block.call actual
         # create typed value and fill in
         struct = TypedValue.new_typed_value func
         struct.store_type  type
         struct.store_value actual
         struct.jit_var
      end
      case call
      when :-
         return do_builtin_math(func) {
            |actual|
            func.insn_sub actual, lval, rval
         }
      when :+
         return do_builtin_math(func) {
            |actual|
            func.insn_add actual, lval, rval
         }
      when :<
         return do_builtin_math(func) {
            |actual|
            func.insn_lt actual, lval, rval
         }
      when :>
         return do_builtin_math(func) {
            |actual|
            func.insn_gt actual, lval, rval
         }
      when :==
         return do_builtin_math(func) {
            |actual|
            func.insn_eq actual, lval, rval
         }
      when :*
         return do_builtin_math(func) {
            |actual|
            func.insn_mul actual, lval, rval
         }
      when :/
         return do_builtin_math(func) {
            |actual|
            func.insn_div actual, lval, rval
         }
      when :%
         return do_builtin_math(func) {
            |actual|
            func.insn_rem actual, lval, rval
         }
      else
         method_name = statement.method_name
      end
   else
      method_name = statement.method_name
   end
   if statement.is_a? Ruby::AST::Call and statement.obj.is_a? Ruby::AST::Const
      raise unless statement.args.nil?
      case statement.obj.value
      when :VByteArray
         case statement.method_name
         when :new
            # create the type value
            type = Value.new
            func.fill_value_with_constant type, :int, $types[:VByteArray]
            # create the value value
            size = Value.new
            func.fill_value_with_constant size, :int, 4096
            alloced_addr = Value.new
            func.insn_call_alloc_bytearray alloced_addr, size
            # create typed value and fill in
            struct = TypedValue.new_typed_value func
            struct.store_type  type
            struct.store_value alloced_addr
            return struct.jit_var
         end
      end
      method_name = "#{statement.obj.value}.#{statement.method_name}"
   end
      case method_name
      when :putchar
         t = statement.args.to_a.first.first
         struct = gen_for_ast func, t, bctx
         struct_tv = TypedValue.wrap_existing_value func, struct
         func.insn_call_print_char struct_tv.value
      when :puts
         t = statement.args.to_a.first.first
         struct = gen_for_ast func, t, bctx
         struct_tv = TypedValue.wrap_existing_value func, struct
         func.insn_call_print_int struct_tv.value
      when :typeof
         t = statement.args.to_a.first.first
         struct = gen_for_ast func, t, bctx
         # create a value to store the retrieved type
         struct_tv = TypedValue.wrap_existing_value func, struct
         type_retr = struct_tv.type
         # create the type value
         type2 = Value.new
         func.fill_value_with_constant type2, :int, $types[:VType]
         # create typed value and fill in
         struct2 = TypedValue.new_typed_value func
         struct2.store_type  type2
         struct2.store_value type_retr
         return struct2.jit_var
      else
         needs_self = false
         if statement.is_a? Ruby::AST::Call
            needs_self = !(statement.obj.is_a? Ruby::AST::Const)
         end
         case statement.method_name
         when :new
            type = Value.new
            func.fill_value_with_constant type, :int, $types[statement.obj.value]
            size = Value.new
            func.fill_value_with_constant size, :int, (4 + 4 + 16 * (3 * 4)) # length, used, 16 * (id, type, value)
            num_elms = Value.new
            func.fill_value_with_constant num_elms, :int, 16
            num_used_elms = Value.new
            func.fill_value_with_constant num_used_elms, :int, 0
            members_addr = Value.new
            func.insn_call_alloc_bytearray members_addr, size
            func.insn_store_relative members_addr, 0, num_elms
            func.insn_store_relative members_addr, 4, num_used_elms
            # create typed value and fill in
            struct = TypedValue.new_typed_value func
            struct.store_type  type
            struct.store_value members_addr
            return struct.jit_var
         end
         is_static = false
         if statement.is_a? Ruby::AST::Call
            if statement.obj.is_a? Ruby::AST::LocalVar
               method_name = "__SELF__.#{statement.method_name}"
            else
               is_static = true
               # isn't this duplicated logic from above?
               method_name = "#{statement.obj.value}.#{statement.method_name}"
            end
         end
         if statement.is_a? Ruby::AST::VCall or statement.args.nil?
            params = []
         else
            param_list = (needs_self ? statement.args : statement.args.to_a.first) || []
            params = []
            if needs_self
               val_struct = gen_for_ast func, statement.obj, bctx
               val_struct_tv = TypedValue.wrap_existing_value func, val_struct
               params << val_struct_tv.type << val_struct_tv.value
            end
            params += param_list.collect { 
                        |arg| 
                        val_struct = gen_for_ast func, arg, bctx
                        val_struct_tv = TypedValue.wrap_existing_value func, val_struct
                        [val_struct_tv.type, val_struct_tv.value]
                     }.flatten
         end
         type_id = nil
         if needs_self
            val_struct = gen_for_ast func, statement.obj, bctx
            val_struct_tv = TypedValue.wrap_existing_value func, val_struct
            type_id = val_struct_tv.type 
         else
            if is_static
                type_id = Value.new
                func.fill_value_with_constant type_id, :int, $types[statement.obj.value]
            else
            type_id = Value.new
            func.fill_value_with_constant type_id, :int, $types[:VGlobal]
            end
         end
         func_id = Value.new
         raise "no such variables/method #{method_name}" unless $func2id.has_key? method_name
         func.fill_value_with_constant func_id, :int, $func2id[method_name]
         func_ptr = Value.new
         func.insn_call_build_function func_ptr, type_id, func_id
         ret_addr = Value.new
         proto = [:int] * params.size
         puts "BUILDING FUNCTION CALL #{method_name} WITH prototype : #{proto.inspect} and param list : #{params.inspect}"
         func.insn_call_indirect_vtable_blah ret_addr, func_ptr, :void_ptr, proto, params
         ret_tv = TypedValue.wrap_existing_address func, ret_addr
         local = TypedValue.new_typed_value func
         local.store_type  ret_tv.type
         local.store_value ret_tv.value
         return local.jit_var
      end
   else
      raise "Got unknown! : #{statement.type}" 
   end
end
def execute_string t, string
   $context = t
   $str_buffer = ""
   block = Ruby.parse string
   func = Function.new t
   func.lock { 
      func.create_with_prototype :int, []
      my_ctx = BlubContext.new
      # for the most random reason *ever* this dummy malloc is needed!!!!
         size = Value.new
         func.fill_value_with_constant size, :int, 4096 # id, next, data (type, value)
         alloced_global_addr = Value.new
         func.insn_call_alloc_bytearray alloced_global_addr, size
      gen_for_ast func, block, my_ctx
      v = Value.new
      func.fill_value_with_constant v, :int, -5
      func.insn_return v
      func.compile
   }
   func.apply []
end

# trivial example:
#   puts 1
# ->
#   FunCall[:puts, ArrayLiteral[[IntegerLiteral[1]]]]

# example:
#   puts 1
#   puts 1 + 1
# becomes:
#   build code for 1
#   tail call to dispatcher
#   build for code puts of 1
#   tail call to dispatcher
# options (
#      build code for 1
#      tail call to dispatcher
#      build code for 1
#      tail call to dispatcher
#      build code for plus 1 + 1
#      tail call to dispatcher
#      build code for puts
#      tail call to dispatcher
# )
#   return out

