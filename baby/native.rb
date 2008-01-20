require 'singleton'
require 'delegate'
require 'src/bench' if !(defined? $labels)
$caller_on = false
$debug_on  = false
$code_on   = false
def dump_caller caller_array
puts caller_array.reject{|line| line =~ /\/test\/unit/}.reverse.join("\n").indent 3
caller_array.first =~ /(.*):(.*?):in/
fname, line_num = $1, $2.to_i
File.open(fname, "r") {
   |file|
   num_to_get = [line_num - 4, line_num].min
   num_to_get.times { file.gets }
   7.times {
      print ((file.lineno+1) == line_num ? "[+] " : "    ")
      puts file.gets
   }
}
end
class Ref
   attr_accessor :data 
   def initialize data
      @data = data
   end
end
class IdentGen
   include Singleton
   attr_accessor :top_ident
   def initialize
      @top_ident = 0
   end
   def get_ident
      tmp = @top_ident
      @top_ident += 1
      tmp
   end
end
class Memory
   attr_reader :ranges, :hits, :misses
   def initialize
      @top_addr = 2**8
      @ranges = {}
      @hits, @misses = 0, 0
      @previous_rng = nil
   end
   def report
      print "Memory report: #{@misses}/#{@hits} (m/h)"
   end
   def format_ranges
      @ranges.map{|rng|rng.inspect}.join("\n").indent 3
   end
   def yield_correct_range addr
      if !@previous_rng.nil? and @previous_rng === addr
         @hits += 1
         yield @previous_rng, @ranges[@previous_rng]
         return
      else 
         @misses += 1
      end
      @ranges.each_pair {
         |rng, data|
         next unless rng === addr
         @previous_rng = rng
         yield rng, data
         break
      }
   end
   def load_elem addr, offs
      found, value = false, nil
   bench("runtime") {
      yield_correct_range(addr) {
         |rng, data|
         value = data[offs]
         raise "loaded a nil element!" if value.nil?
         puts "LOADED #{value} AT #{addr} + #{offs}\nFROM\n#{format_ranges}" if $debug_on
         found = true
      }
      raise "can't find ptr!!!! - #{addr} + #{offs}" unless found
   }
      value
   end
   def store_elem addr, offs, value
      found = false
   bench("runtime") {
      yield_correct_range(addr) {
         |rng, data|
         puts "STORING #{value} AT #{addr} + #{offs}\nIN\n#{format_ranges}, WAS == #{data[offs]}" if $debug_on
         data[offs] = value
         found = true
      }
   }
      raise "can't find ptr!!!! - #{addr} + #{offs}" unless found
   end
   def ptr2string ptr, size
      found, value = nil, nil
   bench("runtime") {
      yield_correct_range(ptr) {
         |rng, data|
         subset = data[(ptr - rng.first) / 4, size / 4] || [] # range with zero size -> nil || []
         ((size / 4) - subset.size).times { subset << nil } if subset.size != (size / 4)
         raise "ARGH! - #{subset.size} != #{(size / 4)}" if subset.size != (size / 4)
         puts "LOADING #{subset.inspect} AT #{ptr}..#{ptr + size}\nFROM\n#{format_ranges}" if $debug_on
         found = true
         value = subset.map { |int| (int.is_a? Function) ? -666 : int }.pack("i*")
      }
   }
      raise "can't find ptr!!!! - #{ptr} .. #{ptr + size}" unless found
      value
   end
   def string2ptr str
      bytes = [str.length, 2]
      str.each_byte { |b| bytes += [b, 2] }
      allocate str.length + 1, bytes
   end
   def allocate size, object
      raise "argh, out of memory!" if @top_addr > 2**32
      # raise "eek! size isn't a multiple of 4!" if (size % 4) != 0
      address = @top_addr
      @ranges[address...(@top_addr + (size*4))] = object
      @top_addr += (size*4) + 2**10
      return address
   end
end
class Context
   attr_accessor :data_inspector, :builder_function, :my_callback
   attr_reader :memory
   def initialize
      @memory = Memory.new
      $memory = @memory
   end
end
class Value
   attr_accessor :ident, :type, :size, :ref
   def initialize
      @ident = IdentGen::instance.get_ident
      @ref   = Ref.new nil
   end
   def value
      @ref.data
   end
   def value= a
      @ref.data = a
   end
   def self.ptr2string ptr, size
      $memory.ptr2string ptr, size
   end
   def self.string2ptr str
      $memory.string2ptr str
   end
end
class Label
   attr_accessor :ident, :pos
   def initialize
      @ident = IdentGen::instance.get_ident
   end
end
Prototype = Struct.new :ret_type, :param_types
Instruction = Struct.new :caller, :insn, :params
class Instruction 
   def inspect
      Struct.new(:insn, :params).new(insn, params.map { |param| ((param.ref.data.is_a? Function) rescue false) ? "<Function>" : param }).inspect
   end
   def to_s
      return "<too much output>" if insn == :insn_call_indirect_vtable_blah
      indent = " " * 3
      "Instruction :: #{insn}" + ([nil] + params).map{|param|param.nil? ? "" : param.inspect}.join("\n#{indent}")
   end
end
class Function
   attr_accessor :context
   def initialize context
      @code = []
      @context = context
      @prototype = nil
      $times = Hash.new { 0 }
   end
   def compile
      # dummy
   end
   def lock
      # todo - lock
      yield
   end
   def fill_value_with_constant val, type, value
      val.type, val.value = type, value
   end
   def fill_value_with_param val, idx
      val.ref = @params[idx].ref
   end
   def create_with_prototype ret_type, param_types
      @prototype = Prototype.new ret_type, param_types
      @params = param_types.map {
         |type|
         param = Value.new
         param.type = type
         param.ref = Ref.new -1
         param
      }
   end
   def method_missing name, *params
      raise "u gotta call create_with_prototype!" if @prototype.nil?
      vars = params
      case name
      when :insn_label
         label = *params
         label.pos = @code.length
      end
      @code << Instruction.new($caller_on ? caller : nil, name, params)
   end
   def create_local value, type
      value.value = nil
      value.type = type
   end
   def apply params
      dispatch params
   end
   def dispatch params
      func = self
      loop {
         func, params = func.exec params
         return params if func.nil?
      }
   end
   def exec params # note - param unused, maybe abstract in layer above, this is the wrong layer!
      result = nil
   bench("exec") {
      catch(:done) {
         params.each_with_index {
            |value, idx|
            @params[idx].ref.data = value
         }
         position = 0
         if $code_on
            puts @code.map {|instr| instr.to_s }.join("\n").indent 3
         end
         hash_math = {  
            :insn_add => :+,
            :insn_sub => :-,
            :insn_mul => :*,
            :insn_div => :/,
            :insn_rem => :%
         } 
         hash_comp = {
            :insn_eq => :==,
            :insn_ne => :==, # see below
            :insn_lt => :<,
            :insn_gt => :>
         }
         math_operators = hash_math.keys + hash_comp.keys
         loop {
            begin
               new_position = position + 1
               instr = @code[position]
               break if instr.nil?
               time = Time.new
               case instr.insn
               when *math_operators
                  ret, src1, src2 = *instr.params
                  bool_result = hash_comp.has_key? instr.insn
                  value = src1.value.send((hash_math.merge hash_comp)[instr.insn], src2.value)
                  ret.value = bool_result ? (value ? 1 : 0) : value
                  ret.value = (1 - ret.value) if instr.insn == :insn_ne
               when :insn_branch_if, :insn_branch_if_not
                  cond, label = *instr.params
                  expected_value = (instr.insn == :insn_branch_if_not) ? 0 : 1
                  new_position = label.pos if cond.value == expected_value
               when :insn_branch
                  label = *instr.params
                  new_position = label.pos
               when :insn_return
                  val = *instr.params
                  result = [nil, val.value]
                  throw :done
               when :insn_store
                  dst, src = *instr.params
                  dst.value = src.value
               when :insn_call_print_int
                  val = *instr.params
                  if @context.my_callback.nil?
                  puts val.value
                  else
                     @context.my_callback.call val.value
                  end
               when :insn_call_alloc_bytearray
                  addr, size = *instr.params
                  addr.size  = size.value
                  addr.value = @context.memory.allocate(size.value, [])
               when :insn_call_data_inspect
                  p1, p2, p3, p4 = *instr.params
                  @context.data_inspector.call p1.value, p2.value, p3.value, p4.value
               when :insn_call_build_function
                  ret, p2, p3, p4 = *instr.params
                  bench("builder_function") {
                     ret.value = @context.builder_function.call p2.value, p3.value, p4.value
                  }
               when :insn_call_indirect_vtable_blah
                  time = nil
                  ret, func, ret_type, func_prototype, params = *instr.params
                  result = [func.value, params.map{ |param| param.value }]
                  throw :done
               when :insn_store_elem
                  puts "BEFORE store: - #{$memory.ranges.inspect}" if $debug_on
                  addr, idx, src = *instr.params
                  raise "out of bounds! - #{idx.value}" if !addr.size.nil? and idx.value > addr.size
                  $memory.store_elem(addr.value, idx.value, src.value)
                  puts "AFTER store:  - #{$memory.ranges.inspect}" if $debug_on
               when :insn_load_elem
                  puts "DURING load: - #{$memory.ranges.inspect}" if $debug_on
                  dst, addr, idx, type = *instr.params
                  raise "out of bounds! - #{idx.value}" if !addr.size.nil? and idx.value > addr.size
                  dst.type  = type
                  dst.value = $memory.load_elem(addr.value, idx.value)
               when :insn_label
                  #
               else
                  raise "INSTRUCTION #{instr.inspect} NOT HANDLED"
               end
               new_time = Time.new
               $times[instr.insn] += (new_time - time).to_f unless time.nil?
               position = new_position
               if $debug_on
                  dump_caller instr.caller if $caller_on
                  puts "Post-instruction State ::"
                  puts instr.to_s
                  puts
               end
            rescue => e
               if $caller_on
                  dump_caller instr.caller
               else
                  puts "SWITCH ON DEBUGGING! if you want to know more!"
                  p e
               end
               puts e.backtrace.join("\n").indent 3
               puts "Current instruction:"
               puts instr.to_s
               puts "Exception: #{e.inspect}"
               exit
            end
         }
      }
   }
      return *result
   end
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

require "test/unit"

class LoggingContext < Context
  attr_reader :log
  def initialize
    super
    @log = []
    self.my_callback = proc { |b| @log << b }
  end
end

class Test_All < Test::Unit::TestCase
  def test_7
     context = Context.new
     func = Function.new context
     func.create_with_prototype :int, [:int, :int]
     func.lock {
        ret = Value.new
        val1 = get_param func, 0
        val2 = get_param func, 1
        func.insn_add ret, val1, val2
        func.insn_return ret
        func.compile
     }
     assert_equal 7, (func.apply [2, 5])
  end

  def test_6
     context = Context.new
     context.builder_function = proc {
        |p2, p3, dummy|
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
        func.insn_call_build_function func_ptr, mk_constant(func, :int, 2), mk_constant(func, :int, 3), mk_constant(func, :int, -1)
        ret_value = Value.new
        func.insn_call_indirect_vtable_blah ret_value, func_ptr, nil, nil, []
        func.insn_return ret_value
        func.compile
     }
     assert_equal 5, (func.apply [])
  end

  def test_5
     context = Context.new
     context.builder_function = proc {
        |p2, p3, p4|
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
        func.insn_call_build_function func_ptr, mk_constant(func, :int, 0), mk_constant(func, :int, 2), mk_constant(func, :int, 3)
        func.insn_return func_ptr 
        func.compile
     }
     assert_equal 5, (func.apply [])
  end

  def test_4
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
     assert_equal [256, 256, 256, 256], inspect_results
  end

  def test_3
     context = LoggingContext.new
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
     assert_equal [32, 64], context.log
  end

  def test_2
     context = LoggingContext.new
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
     assert_equal [1, 2, 3, 4, 5], context.log
  end

  def test_1
     context = LoggingContext.new
     func = Function.new context
     func.create_with_prototype :int, []
     func.lock {
        ret, val1, val2 = Value.new, Value.new, Value.new
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
     assert_equal [5], context.log
  end

  def test_0
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
end