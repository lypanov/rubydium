# require 'rubydium'
require "test/unit"
require 'nanovm'

class Context
   attr_accessor :data_inspector
   attr_accessor :builder_function
   attr_accessor :my_callback
end
def mk_constant func, constant_type, integer
   return_value = Value.new
   func.fill_value_with_constant return_value, constant_type, integer
   return_value 
end

def get_param func, param_idx
   val = Value.new
   func.fill_value_with_param val, param_idx
   val
end

class TC_MyTest < Test::Unit::TestCase

def test0
   context = Context.new
   func = Function.new context
   func.create_with_prototype :int, []
   func.lock {
      ret, val1, val2 = Value.new, Value.new, Value.new
      func.fill_value_with_constant val1, :int, 2
      func.fill_value_with_constant val2, :int, 3
      func.insn_add ret, val1, val2
      func.insn_return ret
      func.compile
   }
   assert_equal 5, (func.apply [])
end

def test1
   context = Context.new
   out_arr, context.my_callback = [], proc { |s| out_arr << s }
   func = Function.new context
   func.create_with_prototype :int, []
   func.lock {
      ret, val1, val2 = Value.new, Value.new, Value.new
      func.insn_call_print_int mk_constant(func, :int, 5)
      func.fill_value_with_constant val1, :int, 2
      func.fill_value_with_constant val2, :int, 3
      func.insn_add ret, val1, val2
      finished = Label.new
      # test if ne, if not branch to next
      skip_4 = Label.new
      cond = Value.new
      func.insn_ne cond, ret, mk_constant(func, :int, 4)
      func.insn_branch_if cond, skip_4
      # else print it and we're finished
      func.insn_call_print_int mk_constant(func, :int, 4)
      func.insn_branch finished
      func.insn_label skip_4
      # test if ne if not branch to next
      skip_5 = Label.new
      func.insn_eq cond, ret, mk_constant(func, :int, 5)
      func.insn_branch_if_not cond, skip_5
      # else print it and we're finished
      func.insn_call_print_int mk_constant(func, :int, 5)
      func.insn_label skip_5
      func.insn_label finished
      func.compile
   }
   func.apply []
   assert_equal [5, 5], out_arr
end

def test2
   context = Context.new
   out_arr, context.my_callback = [], proc { |s| out_arr << s }
   func = Function.new context
   func.create_with_prototype :int, []
   func.lock {
      counter, temp = Value.new, Value.new
      func.create_local counter, :int
      func.fill_value_with_constant temp, :int, 0
      func.insn_store counter, temp
      # while loop, with a counter
      loop_again = Label.new
      func.insn_label loop_again 
      func.insn_add temp, counter, mk_constant(func, :int, 1)
      func.insn_store counter, temp
      func.insn_call_print_int counter
      cond = Value.new
      func.insn_eq cond, counter, mk_constant(func, :int, 5)
      func.insn_branch_if_not cond, loop_again
      func.compile
   }
   func.apply []
   assert_equal [1, 2, 3, 4, 5], out_arr
end

def test3
   context = Context.new
   out_arr, context.my_callback = [], proc { |s| out_arr << s }
   func = Function.new context
   func.create_with_prototype :int, []
   func.lock {
      mem_addr = Value.new
      func.insn_call_alloc_bytearray mem_addr, mk_constant(func, :int, 4096)
      func.insn_store_elem mem_addr, mk_constant(func, :int, 0), mk_constant(func, :int, 32)
      func.insn_store_elem mem_addr, mk_constant(func, :int, 1), mk_constant(func, :int, 64)
      temp = Value.new
      func.insn_load_elem temp, mem_addr, mk_constant(func, :int, 0), :int
      func.insn_call_print_int temp
      func.insn_load_elem temp, mem_addr, mk_constant(func, :int, 1), :int
      func.insn_call_print_int temp
      func.compile
   }
   func.apply []
   assert_equal [32, 64], out_arr
end

def test4
   context = Context.new
   inspect_results = nil
   context.data_inspector = proc {
      |p1, p2, p3, p4|
      inspect_results = [p1, p2, p3, p4]
   }
   func = Function.new context
   func.create_with_prototype :int, []
   func.lock {
      mem_addr = Value.new
      func.insn_call_alloc_bytearray mem_addr, mk_constant(func, :int, 2)
      func.insn_store_elem mem_addr, mk_constant(func, :int, 0), mk_constant(func, :int, 32)
      func.insn_store_elem mem_addr, mk_constant(func, :int, 1), mk_constant(func, :int, 64)
      func.insn_call_data_inspect mem_addr, mem_addr, mem_addr, mem_addr
      func.compile
   }
   func.apply []
   assert_equal [inspect_results.first.class, inspect_results], [Fixnum, [inspect_results.first] * 4]
end

def test5
   context = Context.new
   context.builder_function = proc {
      |p2, p3, p4, p5|
      p2 + p3 + p4
   }
   func = Function.new context
   func.create_with_prototype :int, []
   func.lock {
      mem_addr = Value.new
      func.insn_call_alloc_bytearray mem_addr, mk_constant(func, :int, 2)
      func.insn_store_elem mem_addr, mk_constant(func, :int, 0), mk_constant(func, :int, 32)
      func.insn_store_elem mem_addr, mk_constant(func, :int, 1), mk_constant(func, :int, 64)
      func_ptr = Value.new
      func.insn_call_build_function func_ptr, mk_constant(func, :int, 0), mk_constant(func, :int, 2), 
                                    mk_constant(func, :int, 3), mk_constant(func, :ptr, %w(a b c))
      func.insn_return func_ptr
      func.compile
   }
   assert_equal 5, (func.apply [])
end

def test6
   context = Context.new
   context.builder_function = proc {
      |p2, p3, dummy, p4|
      s_context = Context.new
      s_func = Function.new s_context
      s_func.create_with_prototype :int, []
      s_func.lock {
         s_ret, s_val1, s_val2 = Value.new, Value.new, Value.new
         s_func.fill_value_with_constant s_val1, :int, p2
         s_func.fill_value_with_constant s_val2, :int, p3
         s_func.insn_add s_ret, s_val1, s_val2
         s_func.insn_return s_ret
         s_func.compile
      }
      s_func
   }
   func = Function.new context
   func.create_with_prototype :int, []
   func.lock {
      mem_addr = Value.new
      func.insn_call_alloc_bytearray mem_addr, mk_constant(func, :int, 2)
      func.insn_store_elem mem_addr, mk_constant(func, :int, 0), mk_constant(func, :int, 32)
      func.insn_store_elem mem_addr, mk_constant(func, :int, 1), mk_constant(func, :int, 64)
      func_ptr = Value.new
      func.insn_call_build_function func_ptr, mk_constant(func, :int, 2), mk_constant(func, :int, 3), 
                                    mk_constant(func, :int, -1), mk_constant(func, :ptr, %w(a b c))
      ret_value = Value.new
      func.insn_call_indirect_vtable_blah ret_value, func_ptr, nil, [], []
      func.insn_return ret_value
      func.compile
   }
   assert_equal 5, (func.apply [])
end

def test7
   context = Context.new
   func = Function.new context
   func.create_with_prototype :int, [:int, :int, :int]
   func.lock {
      ret = Value.new
      val1 = get_param func, 0
      val2 = get_param func, 1
      func.insn_add ret, val1, val2
      func.insn_return ret
      func.compile
   }
   assert_equal 7, (func.apply [2, 5, -1])
end

def test8
   context = Context.new
   context.builder_function = proc {
      |p2, p3, dummy, p4|
      assert_equal %w(a b c), p4
      s_func = Function.new context
      s_func.create_with_prototype :int, [:void_ptr, :void_ptr, :ptr]
      s_func.lock {
         s_ret = Value.new
         s_val1, s_val2 = get_param(s_func, 0), get_param(s_func, 1)
         s_temp1, s_temp2 = Value.new, Value.new
         s_func.insn_load_elem s_temp1, s_val1, mk_constant(s_func, :int, p2), :int
         s_func.insn_load_elem s_temp2, s_val2, mk_constant(s_func, :int, p3), :int
         s_func.insn_add s_ret, s_temp1, s_temp2
         temp = Value.new
         s_func.insn_add temp, s_temp1, s_temp2
         s_func.insn_return temp
         s_func.compile
      }
      s_func
   }
   func = Function.new context
   func.create_with_prototype :int, []
   func.lock {
      mem_offs1, mem_offs2 = mk_constant(func, :int, 10), mk_constant(func, :int, 5)
      mem_addr1 = Value.new
      func.insn_call_alloc_bytearray mem_addr1, mk_constant(func, :int, 1024)
      func.insn_store_elem mem_addr1, mem_offs1, mk_constant(func, :int, 32)
      mem_addr2 = Value.new
      func.insn_call_alloc_bytearray mem_addr2, mk_constant(func, :int, 1024)
      func.insn_store_elem mem_addr2, mem_offs2, mk_constant(func, :int, 64)
      func_ptr = Value.new
      func.insn_call_build_function func_ptr, mem_offs1, mem_offs2, mk_constant(func, :int, -1), 
                                    mk_constant(func, :ptr, %w(a b c))
      ret_value = Value.new
      func.insn_call_indirect_vtable_blah ret_value, func_ptr, :int, [:void_ptr, :void_ptr, :ptr], [mem_addr1, mem_addr2, mk_constant(func, :ptr, func)]
      func.insn_return ret_value
      func.compile
   }
   assert_equal 96, (func.apply [])
end

def test9
   context = Context.new
   func = Function.new context
   func.create_with_prototype :int, []
   ret_pos = nil
   func.lock {
      ret, val1, val2 = Value.new, Value.new, Value.new
      func.fill_value_with_constant val1, :int, 2
      func.fill_value_with_constant val2, :int, 3
      func.insn_add ret, val1, val2
      ret_pos = func.pos
      func.insn_return ret
      func.compile
      assert_equal 2, func.size
   }
   assert_equal 5, (func.apply [])
   func.lock {
      func.pos = ret_pos
      opcode, ret = *func.instr
      temp = Value.new
      func.insn_add temp, ret, mk_constant(func, :int, 1)
      func.insn_return temp
      func.compile
      assert_equal 3, func.size
   }
   assert_equal 6, (func.apply [])
end

def test10
   context = Context.new
   func = Function.new context
   func.create_with_prototype :int, []
   func.metadata = {}
   assert_equal({}, func.metadata)
end

def test11
   context = Context.new
   out_arr, context.my_callback = [], proc { |s| out_arr << s }
   func = Function.new context
   func.create_with_prototype :int, []
   func.lock {
      counter, temp = Value.new, Value.new
      func.create_local counter, :int
      func.fill_value_with_constant temp, :int, 0
      func.insn_store counter, temp
      func.insn_hit mk_constant(func, :int, 0)
      # while loop, with a counter
      loop_again = Label.new
      func.insn_label loop_again 
      func.insn_hit mk_constant(func, :int, 1)
      func.insn_add temp, counter, mk_constant(func, :int, 1)
      func.insn_store counter, temp
      func.insn_call_print_int counter
      cond = Value.new
      func.insn_eq cond, counter, mk_constant(func, :int, 5)
      func.insn_branch_if_not cond, loop_again
      func.insn_hit mk_constant(func, :int, 3)
      func.compile
   }
   func.apply []
   p func.profile_hash
   assert_equal [1, 2, 3, 4, 5], out_arr
end

def test12
   context = Context.new
   out_arr, context.my_callback = [], proc { |s| out_arr << s }
   func = Function.new context
   func.create_with_prototype :int, []
   func.lock {
      mem_addr, copy_addr = Value.new, Value.new
      func.insn_call_alloc_bytearray mem_addr, mk_constant(func, :int, 4096)
      func.insn_store_elem mem_addr, mk_constant(func, :int, 0), mk_constant(func, :int, 32)
      func.insn_store_elem mem_addr, mk_constant(func, :int, 1), mk_constant(func, :int, 64)
      func.insn_call_alloc_bytearray copy_addr, mk_constant(func, :int, 4096)
      func.insn_call_copy_bytearray copy_addr, mem_addr, mk_constant(func, :int, 4096)
      temp = Value.new
      func.insn_load_elem temp, mem_addr, mk_constant(func, :int, 0), :int
      func.insn_call_print_int temp
      func.insn_load_elem temp, mem_addr, mk_constant(func, :int, 1), :int
      func.insn_call_print_int temp
      func.insn_load_elem temp, copy_addr, mk_constant(func, :int, 0), :int
      func.insn_call_print_int temp
      func.insn_load_elem temp, copy_addr, mk_constant(func, :int, 1), :int
      func.insn_call_print_int temp
      func.compile
   }
   func.apply []
   assert_equal [32, 64, 32, 64], out_arr
end

end

require 'test/unit/ui/console/testrunner'
Test::Unit::UI::Console::TestRunner.run(TC_MyTest)
