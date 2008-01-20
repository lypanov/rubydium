#define uv(src,dst) if (src == Qnil) {rb_bug("dude...");}; Data_Get_Struct(src, ValueSelf, dst);
#define ul(src,dst) Data_Get_Struct(src, LabelSelf, dst);
#define IMPL_OP(opcode, op) \
            dbg(#opcode" - idx:%d\n", idx);           \
            ValueSelf *val1, *val2, *val3; uv(instr->val1, val1); uv(instr->val2, val2); uv(instr->val3, val3); \
            val1->value.int_val = val2->value.int_val op val3->value.int_val;                                   \
            dbg("  : %d <- %d, %d\n", val1->value.int_val, val2->value.int_val, val3->value.int_val);
#define raise_error(block) {                          \
            VALUE args[2];                            \
            char buf[512];                            \
            block;                                    \
            args[0] = rb_str_new2(buf);               \
            args[1] = self;                           \
            VALUE exception = rb_class_new_instance(2, args, rb_const_get(rb_cObject, rb_intern("NanoVMException"))); \
            rb_exc_raise(exception);                  \
         }
Instruction: INSN_EQ
            IMPL_OP(INSN_EQ,  ==);
Instruction: INSN_NE
            IMPL_OP(INSN_NE,  !=);
Instruction: INSN_ADD
            IMPL_OP(INSN_ADD, +);
Instruction: INSN_SUB
            IMPL_OP(INSN_SUB, -);
Instruction: INSN_MUL
            IMPL_OP(INSN_MUL, *);
Instruction: INSN_DIV
            IMPL_OP(INSN_DIV, /);
Instruction: INSN_REM
            IMPL_OP(INSN_REM, %);
Instruction: INSN_LT
            IMPL_OP(INSN_LT,  <);
Instruction: INSN_GT
            IMPL_OP(INSN_GT,  >);
Instruction: INSN_NOP
            dbg("INSN_NOP - idx:%d\n", idx);
Instruction: INSN_BR
            dbg("INSN_BR  - idx:%d\n", idx);
            LabelSelf *lab; ul(instr->val1, lab);
            if (lab->idx == -1) 
               rb_bug("erm. not branch to label failed!");
            new_idx   = lab->idx;
            new_instr = &(func->instruction_stream[new_idx]);
Instruction: INSN_BRI
            dbg("INSN_BRI - idx:%d\n", idx);
            ValueSelf *cond; LabelSelf *lab; uv(instr->val1, cond); ul(instr->val2, lab);
            if (cond->value.int_val) {
               if (lab->idx == -1) 
                  rb_bug("erm. conditional branch to label failed!");
               new_idx   = lab->idx;
               new_instr = &(func->instruction_stream[new_idx]);
            }
            dbg("  : cond - %d\n", cond->value.int_val);
Instruction: INSN_BRN
            dbg("INSN_BRN - idx:%d\n", idx);
            ValueSelf *cond; LabelSelf *lab; uv(instr->val1, cond); ul(instr->val2, lab);
            if (!cond->value.int_val) {
               if (lab->idx == -1) 
                  rb_bug("erm. conditional not branch to label failed!");
               new_idx   = lab->idx;
               new_instr = &(func->instruction_stream[new_idx]);
            }
            dbg("  : cond - %d\n", cond->value.int_val);
Instruction: INSN_ST
            dbg("INSN_ST  - idx:%d\n", idx);
            // TODO CHECK THAT ITS NOT A CONSTANT
            ValueSelf *dst, *src; uv(instr->val1, dst); uv(instr->val2, src);
            dst->value.int_val = src->value.int_val;
            dbg("  : %d\n", src->value.int_val);
Instruction: INSN_RET
            dbg("INSN_RET - idx:%d\n", idx);
            ValueSelf *val1; uv(instr->val1, val1);
            Dispatch *d;
            d = ALLOC(Dispatch);
            d->params        = INT2NUM(val1->value.int_val);
            d->next_function = Qnil;
            return d;
Instruction: INSN_HIT
            dbg("INSN_HIT - idx:%d\n", idx);
            ValueSelf *val; uv(instr->val1, val);
            dbg("increasing hit count for [%d] - %p\n", val->value.int_val, val);
            if (func->profile_hash == Qnil) {
               func->profile_hash = rb_hash_new();
            }
            VALUE key = INT2NUM(val->value.int_val);
            VALUE hit_count = rb_hash_aref(func->profile_hash, key);
            if (hit_count == Qnil) {
               rb_hash_aset(func->profile_hash, key, INT2NUM(1));
            } else {
               rb_hash_aset(func->profile_hash, key, INT2NUM(NUM2INT(hit_count) + 1));
            }
Instruction: INSN_HOT
            dbg("INSN_HOT - idx:%d\n", idx);
            ValueSelf *cond; uv(instr->val1, cond); ValueSelf *id; uv(instr->val2, id); ValueSelf *ceiling; uv(instr->val3, ceiling);
            dbg("testing hit count for [%d] against [%d]\n", id->value.int_val, ceiling->value.int_val);
            int hit = 0;
            if (func->profile_hash != Qnil) {
               VALUE key = INT2NUM(id->value.int_val);
               VALUE hit_count = rb_hash_aref(func->profile_hash, key);
               if (hit_count != Qnil) {
                  if (NUM2INT(hit_count) > ceiling->value.int_val) {
                     hit = 1;
                  }
               }
            }
            cond->value.int_val = hit;
Instruction: INSN_CPI
            dbg("INSN_CPI - idx:%d\n", idx);
            ValueSelf *val; uv(instr->val1, val);
            dbg("call_print_int :: %d - %p\n", val->value.int_val, val);
            VALUE context, my_callback;
            context     = rb_iv_get(self,    "@context");
            my_callback = rb_iv_get(context, "@my_callback");
            rb_funcall(my_callback, g_call_intern, 1, INT2NUM(val->value.int_val));
Instruction: INSN_CBF
            VALUE context, builder_function, *value_ptr;
            context          = rb_iv_get(self,    "@context");
            builder_function = rb_iv_get(context, "@builder_function");
            dbg("INSN_CBF - idx:%d\n", idx);
            ValueSelf *ret, *v1, *v2, *v3, *v4;
            uv(instr->val1, ret); uv(instr->val2, v1); uv(instr->val3, v2); uv(instr->val4, v3); uv(instr->val5, v4);
            VALUE retval = rb_funcall(builder_function, g_call_intern, 4, 
                                      INT2NUM((int)v1->value.ptr_val), INT2NUM((int)v2->value.ptr_val), 
                                      INT2NUM((int)v3->value.ptr_val), 
                                      (v4->value.value_ptr && (v4->value.value_ptr != (void*)0xDEADBEEF)) 
                                         ? (*v4->value.value_ptr) 
                                         : Qnil);
            if (FIXNUM_P(retval)) {
               ret->value.int_val = NUM2INT(retval);
            } else {
#if DEBUG
               dbg("retval: ");
               if (debug_on) {
                  rb_funcall(retval, rb_intern("display"), 0);
               }
               dbg("\n");
#endif
               value_ptr    = ALLOC(VALUE);
               (*value_ptr) = retval;
               ret->value.value_ptr = value_ptr;
            }
Instruction: INSN_CDI
            VALUE context, data_inspector;
            context        = rb_iv_get(self,    "@context");
            data_inspector = rb_iv_get(context, "@data_inspector");
            dbg("INSN_CDI - idx:%d\n", idx);
            ValueSelf *v1, *v2, *v3, *v4; 
            uv(instr->val1, v1); uv(instr->val2, v2); uv(instr->val3, v3); uv(instr->val4, v4);
            rb_funcall(data_inspector, g_call_intern, 4, 
                       INT2NUM((int)v1->value.ptr_val), INT2NUM((int)v2->value.ptr_val), 
                       INT2NUM((int)v3->value.ptr_val), INT2NUM((int)v4->value.ptr_val));
Instruction: INSN_CCF
            dbg("INSN_CCF - idx:%d\n", idx);
            ValueSelf *ret, *func_ptr; uv(instr->val1, ret); uv(instr->val2, func_ptr);
            VALUE params_param = rb_ary_new();
            dbg("TYPE(instr->val3) ->  %d\n", TYPE(instr->val3));
            int proto_len  = RARRAY(instr->val4)->len;
            int actual_len = RARRAY(instr->val5)->len;
            int bind_idx   = 0;
            if (proto_len != actual_len) {
               rb_bug("prototype does not match with param list");
            }
            for ( ; bind_idx < actual_len; bind_idx++) {
               VALUE entry = rb_ary_entry(instr->val5, bind_idx);        // runtime
               ValueSelf *value; uv(entry, value);
               dbg(" pushing (ValueSelf)%p as param with value %d (%p)\n", value, value->value.int_val, value->value.int_val);
               rb_ary_push(params_param, INT2NUM(value->value.int_val)); // compiletime
            }
            dbg("prototype size (%d) == (%d)\n", proto_len, actual_len);
            dbg("  : calling - %p\n", func_ptr->value.value_ptr);
            Dispatch *d;
            d = ALLOC(Dispatch);
            d->params        = params_param;
            d->next_function = *(func_ptr->value.value_ptr);
            return d;
Instruction: INSN_BAC
            dbg("INSN_BAC - idx:%d\n", idx);
            ValueSelf *dst, *src, *siz; uv(instr->val1, dst); uv(instr->val2, src); uv(instr->val3, siz);
            // if (dst->size < src->size)
               // raise_error({snprintf(buf, 512, "BAC %d, %d", dst->size, src->size);});
            memcpy(dst->value.ptr_val, src->value.ptr_val, siz->value.int_val * 4);
            dbg(" memcpy(%p, %p, %d)\n", dst->value.int_val, src->value.int_val, siz->value.int_val);
Instruction: INSN_CBA
            dbg("INSN_CBA - idx:%d\n", idx);
            ValueSelf *ret, *siz; uv(instr->val1, ret); uv(instr->val2, siz);
            ret->value.ptr_val = malloc(siz->value.int_val * 4);
            ret->size = siz->value.int_val;
            // if (ret->size == 0)
               // raise_error({snprintf(buf, 512, "CBA %d", ret->size);});
            dbg("  : %p <- malloc(%d)\n", ret->value.int_val, siz->value.int_val);
Instruction: INSN_SBA
            dbg("INSN_SBA - idx:%d\n", idx);
            ValueSelf *ptr, *offs, *val; uv(instr->val1, ptr); uv(instr->val2, offs); uv(instr->val3, val);
            *(int *)(ptr->value.ptr_val + (offs->value.int_val * sizeof(int))) = val->value.int_val;
            dbg("  : %p[%d] = %d\n", ptr->value.ptr_val, offs->value.int_val, val->value.int_val);
            // if (offs->value.int_val > ptr->size)
               // raise_error({snprintf(buf, 512, "SBA (%i). %i > %i", idx, offs->value.int_val, ptr->size);});
Instruction: INSN_LBA
            dbg("INSN_LBA - idx:%d\n", idx);
            // todo - type handling
            ValueSelf *ret, *ptr, *offs; uv(instr->val1, ret); uv(instr->val2, ptr); uv(instr->val3, offs);
            dbg("  : %p[%d]\n", ptr->value.ptr_val, offs->value.int_val);
            ret->value.int_val = *(int *)(ptr->value.ptr_val + (offs->value.int_val * sizeof(int)));
            dbg("  : %p[%d] == %d\n", ptr->value.ptr_val, offs->value.int_val, ret->value.ptr_val);
            // if (offs->value.int_val > ptr->size)
               // raise_error({snprintf(buf, 512, "LBA (%i). %i > %i", idx, offs->value.int_val, ptr->size);});