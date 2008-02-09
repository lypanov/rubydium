require "test/unit"

$int_re   = /(-)?\d+/
$float_re = /#{$int_re}\.#{$int_re}/
$reg_re   = /[a-z_][a-z0-9_]*/
$type_re  = $reg_re
$local_re = /'#{$reg_re}/
$label_re = /:#{$reg_re}/
$fcall_re = /&#{$reg_re}/

def parse_itr code
   param_re        = /(#{$float_re}|#{$int_re}|#{$reg_re}|#{$local_re}|#{$label_re}|#{$fcall_re})/
   instr_re        = /%?\w+?(\(\w+?\))?/
   parse_line_re   = /(^\s*(#{instr_re})( (#{param_re})|$)|^\s*(#{$label_re})$)/
   parse_remaining = /(,\s*?#{param_re})/
   code.each_line {
      |line|
      line.chomp!
      match  = parse_line_re.match(line)
      str    = match.post_match
      instr  = match[10] ? "def_label" : match[2]
      instr.gsub!(/#{Regexp.quote(match[3])}/, "") if match[3]
      params = []
      params << match[3].gsub(/\((.*?)\)/, "\\1") if match[3]
      params << match[5] if match[5]
      params << match[10] if match[10]
      if !str.empty?
         while true
            match = str.match parse_remaining
            params << match[2]
            str   = match.post_match
            break unless str
            break if str.empty?
         end
      end
      yield instr, params
   }
end

def InstrHandler *arr, &block
    [block] + arr
end

$accepts_hash = {
   :"%local" => 
      InstrHandler(:acpt_type, :acpt_local) { |func,pr| 
         func.create_local pr[1], pr[0] 
      },
   :"%args" => 
      InstrHandler(:acpt_num) { |func,pr| 
         ; 
      },
   :"%func" => 
      InstrHandler(:acpt_reg) { |func,pr| 
         ; 
      },
   :def_label => 
      InstrHandler(:acpt_label) { |func,pr| 
         func.insn_label pr[0] 
      },
   :load_imm => 
      InstrHandler(:acpt_reg, :acpt_num) { |func,pr| 
         func.fill_value_with_constant pr[0], :int, pr[1] 
      },
   :load_arg => 
      InstrHandler(:acpt_reg, :acpt_num) { |func,pr| 
         func.fill_value_with_param pr[0], pr[1] 
      },
   :add => 
      InstrHandler(:acpt_var, :acpt_value, :acpt_value) { |func,pr| 
         func.insn_add pr[0], pr[1], pr[2] 
      },
   :return => 
      InstrHandler(:acpt_value) { |func,pr| 
         func.insn_return pr[0] 
      },
   :store => 
      InstrHandler(:acpt_local, :acpt_value) { |func,pr| 
         func.insn_store pr[0], pr[1] 
      },
   :is_eq => 
      InstrHandler(:acpt_var, :acpt_value, :acpt_value) { |func,pr| 
         func.insn_eq pr[0], pr[1], pr[2] 
      },
   :branch_if_not => 
      InstrHandler(:acpt_var, :acpt_value) { |func,pr| 
         func.insn_branch_if_not pr[0], pr[1] 
      },
   :out => 
      InstrHandler(:acpt_value) { |func,pr|
         func.insn_call_print_int pr[0] 
      },
   :alloc_bytearray => 
      InstrHandler(:acpt_var, :acpt_value) { |func,pr| 
         func.insn_call_alloc_bytearray pr[0], pr[1] 
      },
   :load_elem => 
      InstrHandler(:acpt_reg, :acpt_value, :acpt_value, :acpt_type) { |func,pr| 
         func.insn_load_elem pr[0], pr[1], pr[2], pr[3]
      },
   :store_elem => 
      InstrHandler(:acpt_reg, :acpt_value, :acpt_value) { |func,pr| 
         func.insn_store_elem pr[0], pr[1], pr[2] 
      },
   :calli =>
      InstrHandler(:acpt_reg) { |func,pr| 
         ret_value = Value.new
         ret_type, prototype = :int, []
         params = []
         fname = pr[0].slice(1..-1)
         func_ptr_value = mk_constant(func, :ptr, $gen_funcs[fname])
         func.insn_call_indirect_vtable_blah ret_value, func_ptr_value, ret_type, prototype, params 
      },
   :call_builder => 
      InstrHandler(:acpt_reg, :acpt_value, :acpt_value, :acpt_value, :acpt_value) { |func,pr| 
         func.insn_call_build_function pr[0], pr[1], pr[2], pr[3], pr[4]
      },
   :callind =>
      InstrHandler(:acpt_reg, :acpt_reg, :acpt_value, :acpt_value, :acpt_value) { |func,pr| 
         func.insn_call_indirect_vtable_blah pr[0], pr[1], :int, [:void_ptr, :void_ptr, :ptr], [pr[2], pr[3], pr[4]]
      },
}

def assert_accepts params, accepts
   accepts.each_with_index {
      |acpt, idx|
      param = params[idx]
      ok = case acpt
           when :acpt_type
              (param =~ $type_re)
           when :acpt_num
              (param =~ $int_re) || (param =~ $float_re)
           when :acpt_reg
              (param =~ $reg_re)
           when :acpt_local
              (param =~ $local_re)
           when :acpt_value
              (param =~ $reg_re) || (param =~ $local_re) || (param =~ $int_re) || (param =~ $float_re)
           when :acpt_var
              (param =~ $reg_re) || (param =~ $local_re)
           when :acpt_label
              (param =~ $label_re)
           when :acpt_fcall
              (param =~ $fcall_re)
           end 
      puts "#{acpt.inspect} -> #{param.inspect} -> #{ok.inspect} (ok?)"
      fail "sorry, you fucked up" unless ok
   }
end

def preparse code
   regs, locals, labels = [], [], []
   parse_itr(code) {
      |instr, params|
      accepts = $accepts_hash[instr.to_sym]
      if accepts.nil?
         puts "warn, no accepts!" 
         next
      end
      accepts = accepts[1..-1]
      accepts.each_with_index {
         |type, idx|
         case params[idx]
         when /^#{$reg_re}$/
            regs << params[idx]
         when /^#{$local_re}$/
            locals << params[idx]
         when /^#{$label_re}$/
            labels << params[idx]
         end
      }
      assert_accepts params, accepts
   }
   return regs, locals, labels
end

def generate func, code
   regs, locals, labels = preparse(code)
   reg_hash, label_hash = {}, {}
   (regs + locals).each {
      |reg_name|
      reg_hash[reg_name.to_sym] = Value.new
   }
   labels.each {
      |label_name|
      label_hash[label_name.to_sym] = Label.new
   }
   parse_itr(code) {
      |instr, params|
      accepts = $accepts_hash[instr.to_sym]
      fail "could't find prototype for #{instr}" unless accepts
      pr = []
      accepts = accepts[1..-1]
      accepts.each_with_index { 
         |acpt, idx|
         case params[idx]
         when /^#{$fcall_re}$/
            pr[idx] = params[idx]
         when /^#{$int_re}$/
            pr[idx] = (acpt == :acpt_value) ? mk_constant(func, :int, params[idx].to_i) : params[idx].to_i
         when /^#{$reg_re}$/, /^#{$local_re}$/
            pr[idx] = (acpt == :acpt_type) ? params[idx].to_sym : reg_hash[params[idx].to_sym]
         when /^#{$label_re}$/
            pr[idx] = label_hash[params[idx].to_sym]
         else
            fail "ur fucked - you don't handle #{acpt.inspect} as an accept type yet!"
         end
      }
      if handler = $accepts_hash[instr.to_sym].first
         handler.call func, pr
      else
         fail "you don't handle - #{instr} : #{params.inspect}"
      end
   }
   func.compile
end

def create_reg
   $max ||= 0
   tmp = "r#{$max}"
   $max += 1
   tmp
end

def val_t t
   name = nil
   reg  = $val2reg[t]
   return reg if reg
   if t.is_a? Label
      if $possible_label_positions[t.jump_pos] == "nop"
         $possible_label_positions[t.jump_pos].replace ":#{create_reg}"
      end
      name = $possible_label_positions[t.jump_pos]
   else
     if t.is_a? Symbol
         name = t
     else
      if t.nil?
         ttype = :reg
      else
         ttype = t.type
      end
      case ttype
      when :const
         name = "#{create_reg}"
         $main << "load_imm #{name}, #{t.as_int}"
      when :local
         name = "'#{create_reg}"
         $pre  << "%local(int) #{name}\n"
      when :reg
         name = create_reg
      when :param
         $args += 1
         arg_idx = $param_bindings.index t
         name = create_reg
         $main << "load_arg #{name}, #{arg_idx}"
      else 
         fail "sorry, unhandled value! - #{t.inspect} -> #{t.type.inspect}"
      end
     end
   end
   $val2reg[t] = name
   name
end

def dump_instructions func
   puts "\n\nDUMPING!\n"
   $param_bindings = func.param_bindings
   ops = %w(insn_nop insn_add insn_ret insn_br insn_bri insn_brn insn_eq insn_ne 
            insn_cpi insn_st insn_cba insn_lba insn_sba insn_cdi insn_cbf insn_ccf 
            insn_sub insn_mul insn_div insn_rem insn_lt insn_gt insn_hit insn_bac)
   id2opcode = ops.inject({}) { |hash, opcode| hash[(ops.index opcode) + 6] = opcode.to_sym; hash }
   labels, locals, regs = [], [], []
   func.pos = 0
   $main = []
   $pre  = ""
   $val2reg = {}
   $possible_label_positions = {}
   $args = 0
   l = 0
   func.size.times {
      i = func.instr
      comment = func.instr_comment
      opcode = id2opcode[i[0]]
      t = [opcode, i[1..-1]]
      case opcode.to_sym
      when :insn_add, :insn_sub, :insn_mul, :insn_eq, :insn_lt
         dst, src1, src2 = *i[1..-1]
         rsrc1, rsrc2, rdst = (val_t src1), (val_t src2), (val_t dst)
         $main << "#{opcode.to_s} #{rdst}, #{rsrc1}, #{rsrc2}"
      when :insn_ret
         src = *i[1]
         $main << "return #{val_t src}"
      when :insn_cpi
         src = *i[1]
         $main << "out #{val_t src}"
      when :insn_st
         dst, src = *i[1..-1]
         rsrc, rdst = (val_t src), (val_t dst)
         $main << "store #{rdst}, #{rsrc}"
      when :insn_nop
         # a nop can be a label placeholder
         mystring = "nop"
         $possible_label_positions[func.pos] = mystring
         $main << mystring
      when :insn_hit
         x = *i[1..-1]
         rx = (val_t x)
         $main << "branch #{rx}"
      when :insn_br
         label = *i[1..-1]
         rlabel = (val_t label)
         $main << "branch #{rlabel}"
      when :insn_bri
         cond, label = *i[1..-1]
         rcond, rlabel = (val_t cond), (val_t label)
         $main << "branch_if #{rcond}, #{rlabel}"
      when :insn_brn
         cond, label = *i[1..-1]
         rcond, rlabel = (val_t cond), (val_t label)
         $main << "branch_if_not #{rcond}, #{rlabel}"
      when :insn_cba
         dst, src = *i[1..-1]
         rdst, rsrc = (val_t dst), (val_t src)
         $main << "alloc_bytearray #{rdst}, #{rsrc}"
      when :insn_bac
         dst, src, size = *i[1..-1]
         rdst, rsrc, rsize = (val_t dst), (val_t src), (val_t size)
         $main << "bytearray_copy #{rdst}, #{rsrc}, #{rsize}"
      when :insn_sba
         mem, offs, data = *i[1..-1]
         rmem, roffs, rdata = (val_t mem), (val_t offs), (val_t data)
         $main << "store_elem #{rmem}, #{roffs}, #{rdata}"
      when :insn_lba
         dst, mem, offs, type = *i[1..-1]
         rdst, rmem, roffs, rtype = (val_t dst), (val_t mem), (val_t offs), (val_t type)
         $main << "load_elem #{rdst}, #{rmem}, #{roffs}, #{rtype}"
      when :insn_cdi
         p1, p2, p3, p4 = *i[1..-1]
         rp1, rp2, rp3, rp4 = (val_t rp1), (val_t rp2), (val_t rp3), (val_t rp4)
         $main << "data_inspect #{rp1}, #{rp2}, #{rp3}, #{rp4}"
      when :insn_ccf
         $main << "call_function (FIXME IMPLEMENT)"
         # TODO
      when :insn_cbf
         $main << "call_function (FIXME IMPLEMENT)"
         # TODO
      else
         fail "dump_instructions: you don't handle #{t.inspect} yet!"
      end
      $main[-1][0, 0] = (func.pos.to_s + ": ").ljust(4);
      $main[-1][$main[-1].length, 0] = "[ #{comment} ]".rjust(64 - $main[-1].length)
      func.pos += 1
   }
   puts "%args #{$args}\n" + $pre
   puts $main
end

class Assembler
   attr_accessor :context, :funcs, :outs

   def initialize context
      @context = context
      @outs    = []
      @funcs   = {}
      @context.my_callback = proc { |s| @outs << s }
   end

   def parse_code code
      func = ""
      code.each_line {
         |line|
         start_func = (line =~ /%func\s*([a-z_][a-z_0-9]*)/)
         if start_func
            func = line
            @funcs[$1] = func
         else
            func << line
         end
      }
      if @funcs.empty?
         @funcs = { "main" => code }
      end
   end

   def assemble prototype
      @funcs.each_pair {
         |name, src|
         func = Function.new @context
         func.create_with_prototype :int, prototype
         func.lock { 
            generate func, src 
         }
         @funcs[name] = func
      }
   end
end

def do_blah code, expected, args = [], expected_outs = nil, assembler = nil
   assembler = Assembler.new(Context.new) if assembler.nil?
   assembler.parse_code code
   $gen_funcs = assembler.funcs 
   assembler.assemble([:int] * args.length) # FIXME - this should be done due to %args in parse
   res = $gen_funcs["main"].apply(args)
   if !expected_outs.nil?
      assert_equal expected_outs, assembler.outs
   else
      assert_equal expected, res
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

class TC_MyTest < Test::Unit::TestCase

def test0
   do_blah <<CODE, 5
      load_imm r0, 2
      load_imm r1, 3
      add r2, r0, r1
      return r2
CODE
end

def test1
   do_blah <<CODE, nil, [], [1, 2, 3, 4, 5]
      %local(int) 'counter
      load_imm temp, 0
      store 'counter, temp
   :loop_again
      load_imm temp1, 1
      add temp, 'counter, temp1
      store 'counter, temp
      out 'counter
      load_imm temp5, 5
      is_eq cond, 'counter, temp5
      branch_if_not cond, :loop_again
CODE
end

def test2
   do_blah <<CODE, 7, [2, 5]
      %args 2
      load_arg val1, 0
      load_arg val2, 1
      add ret, val1, val2
      return ret
CODE
end

def test3
   do_blah <<CODE, 0, []
      alloc_bytearray mem_addr1, 1024
      store_elem mem_addr1, 10, 32
      alloc_bytearray mem_addr2, 1024
      store_elem mem_addr2, 5, 64
      load_elem tmp1, mem_addr1, 10, int
      out tmp1
      load_elem tmp2, mem_addr2, 5, int
      out tmp2
CODE
end

def test4
   do_blah <<CODE, 7, [], [1, 2]
   %func two
      out 2
   %func main
      out 1
      calli &two
      out 3
CODE
end

def test8
   context = Context.new
   assembler = Assembler.new context
   context.builder_function = proc {
      |p2, p3, dummy, p4|
      code = <<CODE
         %args 3
         load_arg mem_addr1, 0
         load_arg mem_addr2, 1
         load_elem tmp1, mem_addr1, 10, int
         load_elem tmp2, mem_addr2, 5, int
         add return_value, tmp1, tmp2
         return return_value
CODE
      assembler_inner = Assembler.new context
      assembler_inner.outs = assembler.outs # we share the output array, yet not the funcs list (as we have two mains)
      assembler_inner.parse_code code
      assembler_inner.assemble [:void_ptr, :void_ptr, :ptr]
      assembler_inner.funcs["main"]
   }
   do_blah <<CODE, 7, [], nil, assembler
      alloc_bytearray mem_addr1, 1024
      store_elem mem_addr1, 10, 32
      alloc_bytearray mem_addr2, 1024
      store_elem mem_addr2, 5, 64
      load_elem tmp1, mem_addr1, 10, int
      out tmp1
      load_elem tmp2, mem_addr2, 5, int
      out tmp2
      call_builder func_ptr, 10, 5, -1, 0
      callind ret, func_ptr, mem_addr1, mem_addr2, -1
      return ret
CODE
   # TODO - fix the above prototype - its fixed!
=begin
      func.insn_call_build_function func_ptr, mem_offs1, mem_offs2, mk_constant(func, :int, -1), mk_constant(func, :ptr, %w(a b c))
      func.insn_call_indirect_vtable_blah ret_value, func_ptr, :int, [:void_ptr, :void_ptr, :ptr], [mem_addr1, mem_addr2, mk_constant(func, :ptr, func)]
   }
=end
   assert_equal 96, (func.apply [])
end

end unless $0 != __FILE__
