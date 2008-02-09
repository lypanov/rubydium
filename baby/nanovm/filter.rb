# DUP from tc_all.rb
ops = %w(insn_nop insn_add insn_ret insn_br insn_bri insn_brn insn_eq insn_ne 
         insn_cpi insn_st insn_cba insn_lba insn_sba insn_cdi insn_cbf insn_ccf 
         insn_sub insn_mul insn_div insn_rem insn_lt insn_gt insn_hit insn_bac insn_hot insn_fail)
id2opcode = ops.inject({}) { |hash, opcode| hash[(ops.index opcode) + 6] = opcode.to_sym; hash }
had_one = false
out = ""
def boo out
   out << <<CODE
      dbg("jumping to %d from %d\\n", new_idx, idx);
      idx       = new_idx;
      instr     = new_instr;
      if (idx == func->num_instructions) {
         goto done;
      }
      new_idx   = idx   + 1;
      new_instr = instr + 1;
      func->executed_instructions++;
      goto *instr->precomputed_goto;
      // goto *array[instr->opcode];
   };
CODE
end
instrs = ["invalid"] * ops.size
STDIN.each_line {
   |line|
   line.gsub!(/Instruction: (\w+)/) {
      boo(out) if had_one
      had_one = true
      opcode = $1.downcase
      puts "\n\n\n\n!!!! *** DID YOU FORGET TO DEFINE THE OP IN <filter.rb>? *** !!!! \n\n !!! \n\n PLEASE UPDATE <asm.rb> ALSO!!! \n\n\n\n" if not id2opcode.invert.has_key? opcode.to_sym
      instrs[id2opcode.invert[opcode.to_sym]] = opcode
      "#{opcode}: {"
   }
   out << line
}
boo(out) if had_one
puts <<PRE
static Dispatch* exec_func(VALUE self, VALUE params)
{
   static void *array[] = { #{instrs.map { |t| "&&" + t }.join ", "} };
   FunctionSelf *func;
   Data_Get_Struct(self, FunctionSelf, func);
   Instruction *instr = func->instruction_stream, *new_instr;
   int idx = 0, new_idx, bind_idx;
   dbg("binding %d params from prototype with %d passed params\\n", func->num_params, RARRAY(params)->len);
   // bind params to the local variables (the ValueSelf's that had get_param called)
   for (bind_idx = 0; bind_idx < func->num_params; bind_idx++) {
      VALUE type = rb_ary_entry(func->param_type_syms, bind_idx);
      VALUE val  = rb_ary_entry(func->param_bindings,  bind_idx);
      int unbound = (val == Qnil);
      if (!unbound) {
         ValueSelf *value;
         Data_Get_Struct(val, ValueSelf, value);
         switch(id2jit_type(SYM2ID(type))) {
         case TYPE_INT:
         case TYPE_VOID_PTR:
            value->value.int_val = NUM2INT(rb_ary_entry(params, bind_idx));
            break;
         case TYPE_PTR: {
            *(value->value.value_ptr) = rb_ary_entry(params, bind_idx);
            break;
         }
         default: 
            rb_bug("no type provided!");
         }
      }
   }
   // precompute goto's
   Instruction *pinstr = func->instruction_stream;
   int pidx;
   for (pidx = 0; pidx < func->num_instructions; pidx++) {
      pinstr->precomputed_goto = array[pinstr->opcode];
      pinstr++;
   }
   
PRE
puts <<CODE
      new_idx   = idx;
      new_instr = instr;
      goto insn_nop;
#{out}
   invalid:
      printf("invalid! poopy!\\n");
      exit(1);
   done:
CODE
puts <<POST
  {
   Dispatch *d;
   d = ALLOC(Dispatch);
   d->params        = INT2NUM(0); // clean exit
   d->next_function = Qnil;
   return d;
  }
}
POST
