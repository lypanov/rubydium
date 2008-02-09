#include "ruby.h"

ID g_int_sym_id;
ID g_int_sym_void_ptr;
ID g_call_intern;
ID g_ptr_sym_id;

ID g_const;
ID g_local;
ID g_reg;
ID g_param;

/**** Label CLASS ****/

#include <stdarg.h>

#define DEBUG 1

static debug_on = 0;

static VALUE c_s_debug(VALUE klass, VALUE value) {
   debug_on = (value == Qtrue);
   return Qnil;
}

void dbg(const char *format, ...)
{   
#if DEBUG
   if (debug_on) {
      va_list ap;
      va_start(ap, format);
      vprintf(format, ap);
      va_end(ap);
   }
#endif
}
                               
typedef struct {
   int idx;
} LabelSelf;

static VALUE l_new(VALUE klass)
{
   VALUE argv[0];
   VALUE bul;
   LabelSelf *bt;
   bt = ALLOC(LabelSelf);
   bul = Data_Wrap_Struct(klass, 0, free, bt);
   bt->idx = -1;
   rb_obj_call_init(bul, 0, argv);
   return bul;
}

static VALUE l_init(VALUE self)
{
   LabelSelf *bt;
   Data_Get_Struct(self, LabelSelf, bt);
   return self;
}

static VALUE l_jump_pos(VALUE self)
{
   LabelSelf *bt;
   Data_Get_Struct(self, LabelSelf, bt);
   return INT2NUM(bt->idx);
}

/**** Value CLASS ****/

typedef struct {
   union {
      int int_val;   // int
      void *ptr_val; // void_ptr
      VALUE *value_ptr; // value_ptr
   } value;
   int size; // for bytearrays
   char type;
} ValueSelf;

#define N_local 0
#define N_const 1
#define N_reg   2
#define N_param 3

static VALUE v_new(VALUE klass)
{
   VALUE argv[0];
   VALUE bul;
   ValueSelf *bt;
   bt = ALLOC(ValueSelf);
   bul = Data_Wrap_Struct(klass, 0, free, bt);
   bt->value.ptr_val = (void*)0xDEADBEEF;
   bt->size = -1;
   bt->type = N_reg;
   rb_obj_call_init(bul, 0, argv);
   return bul;
}

static VALUE v_as_int(VALUE self)
{
   ValueSelf *value;
   Data_Get_Struct(self, ValueSelf, value);
   return INT2NUM(value->value.int_val);
}

static VALUE v_as_obj(VALUE self)
{
   ValueSelf *value;
   Data_Get_Struct(self, ValueSelf, value);
   return *(value->value.value_ptr);
}

static VALUE v_type(VALUE self)
{
   ValueSelf *value;
   Data_Get_Struct(self, ValueSelf, value);
   switch(value->type) {
      case N_local:
         return ID2SYM(g_local);
      case N_const:
         return ID2SYM(g_const);
      case N_reg:
         return ID2SYM(g_reg);
      case N_param:
         return ID2SYM(g_param);
   }
   rb_bug("FUCK");
}

static VALUE v_init(VALUE self)
{
   ValueSelf *bt;
   Data_Get_Struct(self, ValueSelf, bt);
   return self;
}

/**** Context CLASS ****/

typedef struct {
   // unused
} ContextSelf;

static VALUE c_new(VALUE klass)
{
   VALUE argv[0];
   VALUE bul;
   ContextSelf *bt;
   bt = ALLOC(ContextSelf);
   bul = Data_Wrap_Struct(klass, 0, free, bt);
   rb_obj_call_init(bul, 0, argv);
   return bul;
}

static VALUE c_init(VALUE self)
{
   ContextSelf *bt;
   Data_Get_Struct(self, ContextSelf, bt);
   return self;
}

/**** Function CLASS ****/

typedef struct {
   void *precomputed_goto;
   char opcode;
   int num_vals;
   VALUE val1;
   VALUE val2;
   VALUE val3;
   VALUE val4;
   VALUE val5;
   VALUE comment;
} Instruction;

typedef struct {
   int allocated;
   int num_instructions;
   int executed_instructions;
   int instruction_idx;
   int return_type;
   int num_params;
   VALUE param_type_syms;
   VALUE param_bindings;
   Instruction *instruction_stream;
   VALUE metadata;
   VALUE profile_hash;
} FunctionSelf;

static void f_mark(FunctionSelf *marked);
static void f_free(FunctionSelf *marked);

static VALUE f_new(VALUE klass, VALUE context)
{
   VALUE bul, argv[1] = {context};
   FunctionSelf *bt;
   bt = ALLOC(FunctionSelf);
   bt->allocated          = 4096; // TODO make this dynamic!
   bt->num_instructions   = 0;
   bt->executed_instructions = 0;
   bt->instruction_idx    = 0;
   bt->instruction_stream = ALLOC_N(Instruction, bt->allocated);
   bt->param_type_syms    = Qnil;
   bt->param_bindings     = Qnil;
   bt->metadata           = Qnil;
   bt->profile_hash       = Qnil;
   bul = Data_Wrap_Struct(klass, f_mark, f_free, bt);
   rb_obj_call_init(bul, 1, argv);
   return bul;
}

static void f_free(FunctionSelf *func)
{
   free(func->instruction_stream);
   free(func);
}

static VALUE f_init(VALUE self, VALUE context)
{
   rb_iv_set(self, "@context", context);
   return self;
}

static VALUE f_metadata(VALUE self)
{
   FunctionSelf *func;
   Data_Get_Struct(self, FunctionSelf, func);
   return func->metadata;
}

static VALUE f_metadata_set(VALUE self, VALUE new_metadata)
{
   FunctionSelf *func;
   Data_Get_Struct(self, FunctionSelf, func);
   func->metadata = new_metadata;
}

static VALUE f_profile_hash(VALUE self)
{
   FunctionSelf *func;
   Data_Get_Struct(self, FunctionSelf, func);
   return func->profile_hash;
}

static VALUE f_param_bindings(VALUE self)
{
   FunctionSelf *func;
   Data_Get_Struct(self, FunctionSelf, func);
   return func->param_bindings;
}

static VALUE f_param_type_syms(VALUE self)
{
   FunctionSelf *func;
   Data_Get_Struct(self, FunctionSelf, func);
   return func->param_type_syms;
}

#define TYPE_INT      32
#define TYPE_VOID_PTR 64
#define TYPE_PTR      96

// todo -  strongly type this with an enum
//

inline static int id2jit_type(ID id) {
   if (id == g_int_sym_id)
	   return TYPE_INT;
   if (id == g_ptr_sym_id)
	   return TYPE_PTR;
   if (id == g_int_sym_void_ptr)
	   return TYPE_VOID_PTR;
   rb_bug("wha?");
}

static VALUE f_pos(VALUE self)
{
   FunctionSelf *func;
   Data_Get_Struct(self, FunctionSelf, func);
   return INT2NUM(func->instruction_idx);
}

static VALUE f_pos_set(VALUE self, VALUE new_value)
{
   FunctionSelf *func;
   Data_Get_Struct(self, FunctionSelf, func);
   func->instruction_idx = NUM2INT(new_value);
}

static VALUE f_size(VALUE self)
{
   FunctionSelf *func;
   Data_Get_Struct(self, FunctionSelf, func);
   return INT2NUM(func->num_instructions);
}

static VALUE f_instructions_executed(VALUE self)
{
   FunctionSelf *func;
   Data_Get_Struct(self, FunctionSelf, func);
   return INT2NUM(func->executed_instructions);
}

static VALUE f_instr(VALUE self)
{
   FunctionSelf *func;
   Data_Get_Struct(self, FunctionSelf, func);
   VALUE arr = rb_ary_new();
   Instruction *instr = &(func->instruction_stream[func->instruction_idx]);
   rb_ary_push(arr, INT2NUM(instr->opcode));
   if (instr->num_vals >= 1) rb_ary_push(arr, instr->val1);
   if (instr->num_vals >= 2) rb_ary_push(arr, instr->val2);
   if (instr->num_vals >= 3) rb_ary_push(arr, instr->val3);
   if (instr->num_vals >= 4) rb_ary_push(arr, instr->val4);
   if (instr->num_vals >= 5) rb_ary_push(arr, instr->val5);
   return arr;
}

static VALUE f_instr_comment(VALUE self)
{
   FunctionSelf *func;
   Data_Get_Struct(self, FunctionSelf, func);
   Instruction *instr = &(func->instruction_stream[func->instruction_idx]);
   return instr->comment;
}

static VALUE f_create_with_prototype(VALUE self, VALUE ret_type_sym, VALUE param_type_syms)
{
   FunctionSelf *func;
   Data_Get_Struct(self, FunctionSelf, func);
   func->num_params = RARRAY(param_type_syms)->len;
   int bind_idx;
   func->param_type_syms = param_type_syms;
   func->param_bindings  = rb_ary_new();
   for (bind_idx = 0; bind_idx < func->num_params; bind_idx++) {
      rb_ary_push(func->param_bindings, Qnil);
   }
   dbg("got prototype with %d params!\n", func->num_params);
   return Qnil;
}

static VALUE f_fill_value_with_param(VALUE self, VALUE val_v, VALUE idx)
{
   FunctionSelf *func;
   Data_Get_Struct(self, FunctionSelf, func);
   ValueSelf *val;
   Data_Get_Struct(val_v, ValueSelf, val);
   val->type = N_param;
   dbg("associating param_bindings idx %d with %p\n", NUM2INT(idx), val);
   rb_ary_store(func->param_bindings, NUM2INT(idx), val_v);
   return Qnil;
}

static VALUE f_fill_value_with_constant(VALUE self, VALUE ret_v, VALUE type_sym, VALUE int_val)
{
   ValueSelf *ret;
   Data_Get_Struct(ret_v, ValueSelf, ret);
   ret->type = N_const;
   switch(id2jit_type(SYM2ID(type_sym))) {
   case TYPE_VOID_PTR:
   case TYPE_INT:
      dbg("%p.fill_value_with_constant - %d\n", ret, NUM2INT(int_val));
      ret->value.int_val = NUM2INT(int_val);
      return Qnil;
   case TYPE_PTR: {
      VALUE *value_ptr;
      value_ptr    = ALLOC(VALUE);
      (*value_ptr) = int_val;
      ret->value.value_ptr = value_ptr;
      return Qnil;
   } }
   rb_bug("naah. dufus. u can't do that");
   return Qnil;
}

static VALUE f_create_local(VALUE self, VALUE ret_v, VALUE type_sym)
{
   ValueSelf *ret;
   Data_Get_Struct(ret_v, ValueSelf, ret);
   ret->type = N_local;
   switch(id2jit_type(SYM2ID(type_sym))) {
   case TYPE_VOID_PTR:
   case TYPE_INT:
      dbg("%p.create_local\n", ret);
      ret->value.int_val = 666;
      return Qnil;
   case TYPE_PTR:
      dbg("%p.create_local - void_ptr\n", ret);
      ret->value.ptr_val = (void*)0xDEADBEEF;
      return Qnil;
   }
   rb_bug("naah. dufus. u can't do that");
   return Qnil;
}

// nop add ret br bri brn eq ne cpi st cba lba sba cdi cbf ccf sub mul div rem lt gt  

#define INSN_NOP 6
#define INSN_ADD 7
#define INSN_RET 8
#define INSN_BR  9
#define INSN_BRI 10
#define INSN_BRN 11
#define INSN_EQ  12
#define INSN_NE  13
#define INSN_CPI 14
#define INSN_ST  15
#define INSN_CBA 16
#define INSN_LBA 17
#define INSN_SBA 18
#define INSN_CDI 19
#define INSN_CBF 20
#define INSN_CCF 21
#define INSN_SUB 22
#define INSN_MUL 23
#define INSN_DIV 24
#define INSN_REM 25
#define INSN_LT  26
#define INSN_GT  27
#define INSN_HIT 28
#define INSN_BAC 29
#define INSN_HOT 30

static void f_mark(FunctionSelf *func)
{
   Instruction *instr = func->instruction_stream;
   dbg("mark called! %d\n", func->num_instructions);
   int n = 0;
   for ( ; n < func->num_instructions; n++) {
      rb_gc_mark(instr->comment);
      if (instr->num_vals >= 1) rb_gc_mark(instr->val1);
      if (instr->num_vals >= 2) rb_gc_mark(instr->val2);
      if (instr->num_vals >= 3) rb_gc_mark(instr->val3);
      if (instr->num_vals >= 4) rb_gc_mark(instr->val4);
      if (instr->num_vals >= 5) rb_gc_mark(instr->val5);
      // FIXME - we have to keep references in the ruby currently, we shouldn't have to, mark ain't working, are we marking the correct things???
      if (instr->opcode == INSN_CCF) {
         ValueSelf *func_ptr; 
         Data_Get_Struct(instr->val2, ValueSelf, func_ptr);
         dbg("CCF: checking function pointer - %p / %d\n", func_ptr->value.value_ptr, func_ptr->value.value_ptr);
         if (func_ptr->value.value_ptr != (void*)0xdeadbeef) {
            dbg("CCF: marking function pointer - %p / %d\n", func_ptr->value.value_ptr, func_ptr->value.value_ptr);
            rb_gc_mark(*(func_ptr->value.value_ptr));
         }
      } else if (instr->opcode == INSN_CBF) {
         ValueSelf *func_ptr;
         Data_Get_Struct(instr->val1, ValueSelf, func_ptr);
         dbg("CBF: checking function pointer - %p / %d\n", func_ptr->value.value_ptr, func_ptr->value.value_ptr);
         if (func_ptr->value.value_ptr != (void*)0xdeadbeef) {
            dbg("CBF: marking function pointer - %p / %d\n", func_ptr->value.value_ptr, func_ptr->value.value_ptr);
            rb_gc_mark(*(func_ptr->value.value_ptr));
         }
         ValueSelf *v4;
         Data_Get_Struct(instr->val5, ValueSelf, v4);
         if (v4->value.value_ptr && (v4->value.value_ptr != (void*)0xDEADBEEF)) {
            dbg("CBF: marking metadata pointer - %p / %d\n", *(v4->value.value_ptr), *(v4->value.value_ptr));
            rb_gc_mark(*(v4->value.value_ptr));
         }
      }
      instr++;
   }
   rb_gc_mark(func->param_type_syms);
   rb_gc_mark(func->param_bindings);
   rb_gc_mark(func->metadata);
   rb_gc_mark(func->profile_hash);
   dbg("mark finished!\n", func->num_instructions);
}

#define CHECK_ASSIGN_VAL(dst, val) { if (val == Qnil) { rb_raise(rb_eArgError, "dude nil argument!"); }; dst = val; }

#define append_insn(insn, block) \
   FunctionSelf *func;                                                       \
   Data_Get_Struct(self, FunctionSelf, func);                                \
   Instruction *instr = &(func->instruction_stream[func->instruction_idx]);  \
   VALUE context, my_callback;                                               \
   context     = rb_iv_get(self,    "@context");                             \
   my_callback = rb_iv_get(context, "@make_comment");                        \
   if (my_callback != Qnil)                                                  \
      instr->comment = rb_funcall(my_callback, g_call_intern, 0);            \
   else                                                                      \
      instr->comment = Qnil;                                                 \
   block;                                                                    \
   if (func->instruction_idx == func->num_instructions)                      \
      func->num_instructions++;                                              \
   func->instruction_idx++;                                                  \
   if (func->num_instructions > func->allocated) {                           \
      rb_bug("too many instructions!");                                      \
   }

#define DEFINE_OPERATOR_INSTR1(func_name, opcode_num) \
static VALUE func_name(VALUE self, VALUE ret)  \
{                                                                      \
   append_insn(insn, {                                                 \
      instr->opcode = opcode_num;                                      \
      instr->val1   = ret;                                             \
      instr->num_vals = 1;                                             \
   });                                                                 \
   return Qnil;                                                        \
}

#define DEFINE_OPERATOR_INSTR2(func_name, opcode_num) \
static VALUE func_name(VALUE self, VALUE ret, VALUE val1)  \
{                                                                      \
   append_insn(insn, {                                                 \
      instr->opcode = opcode_num;                                      \
      CHECK_ASSIGN_VAL(instr->val1, ret);                              \
      CHECK_ASSIGN_VAL(instr->val2, val1);                             \
      instr->num_vals = 2;                                             \
   });                                                                 \
   return Qnil;                                                        \
}

#define DEFINE_OPERATOR_INSTR3(func_name, opcode_num) \
static VALUE func_name(VALUE self, VALUE ret, VALUE val1, VALUE val2)  \
{                                                                      \
   append_insn(insn, {                                                 \
      instr->opcode = opcode_num;                                      \
      CHECK_ASSIGN_VAL(instr->val1, ret);                              \
      CHECK_ASSIGN_VAL(instr->val2, val1);                             \
      CHECK_ASSIGN_VAL(instr->val3, val2);                             \
      instr->num_vals = 3;                                             \
   });                                                                 \
   return Qnil;                                                        \
}

#define DEFINE_OPERATOR_INSTR4(func_name, opcode_num) \
static VALUE func_name(VALUE self, VALUE ret, VALUE val1, VALUE val2, VALUE val3)  \
{                                                                      \
   append_insn(insn, {                                                 \
      instr->opcode = opcode_num;                                      \
      CHECK_ASSIGN_VAL(instr->val1, ret);                              \
      CHECK_ASSIGN_VAL(instr->val2, val1);                             \
      CHECK_ASSIGN_VAL(instr->val3, val2);                             \
      CHECK_ASSIGN_VAL(instr->val4, val3);                             \
      instr->num_vals = 4;                                             \
   });                                                                 \
   return Qnil;                                                        \
}

#define DEFINE_OPERATOR_INSTR5(func_name, opcode_num) \
static VALUE func_name(VALUE self, VALUE ret, VALUE val1, VALUE val2, VALUE val3, VALUE val4)  \
{                                                                      \
   append_insn(insn, {                                                 \
      instr->opcode = opcode_num;                                      \
      CHECK_ASSIGN_VAL(instr->val1, ret);                              \
      CHECK_ASSIGN_VAL(instr->val2, val1);                             \
      CHECK_ASSIGN_VAL(instr->val3, val2);                             \
      CHECK_ASSIGN_VAL(instr->val4, val3);                             \
      CHECK_ASSIGN_VAL(instr->val5, val4);                             \
      instr->num_vals = 5;                                             \
   });                                                                 \
   return Qnil;                                                        \
}

// operators are all ret (1) = val1 (2) op val2 (3)
DEFINE_OPERATOR_INSTR3(f_insn_ne,  INSN_NE);
DEFINE_OPERATOR_INSTR3(f_insn_eq,  INSN_EQ);
DEFINE_OPERATOR_INSTR3(f_insn_add, INSN_ADD);
DEFINE_OPERATOR_INSTR3(f_insn_sub, INSN_SUB);
DEFINE_OPERATOR_INSTR3(f_insn_mul, INSN_MUL);
DEFINE_OPERATOR_INSTR3(f_insn_div, INSN_DIV);
DEFINE_OPERATOR_INSTR3(f_insn_rem, INSN_REM);
DEFINE_OPERATOR_INSTR3(f_insn_lt,  INSN_LT);
DEFINE_OPERATOR_INSTR3(f_insn_gt,  INSN_GT);

// branch to an address (1)
DEFINE_OPERATOR_INSTR1(f_insn_branch,               INSN_BR);

// branch or not to an address (1) given a conditional (2)
DEFINE_OPERATOR_INSTR2(f_insn_branch_if,            INSN_BRI);
DEFINE_OPERATOR_INSTR2(f_insn_branch_if_not,        INSN_BRN);

// returns a value (1)
DEFINE_OPERATOR_INSTR1(f_insn_return,               INSN_RET);

// stores into a variables (1) the value of another (2)
DEFINE_OPERATOR_INSTR2(f_insn_store,                INSN_ST);

// prints a value (1)
DEFINE_OPERATOR_INSTR1(f_insn_call_print_int,       INSN_CPI);

// calls context.data_inspector with four params (1) (2) (3) and (4), no return value
DEFINE_OPERATOR_INSTR4(f_insn_call_data_inspect,    INSN_CDI);

// calls context.builder_function returns function pointer (1) and passes 4 params in (2), (3), (4) and (5)
DEFINE_OPERATOR_INSTR5(f_insn_call_build_function,  INSN_CBF);

// returns value (1) by calling function pointer (2) with return value (3) and param prototype (4) with the values in (5)
DEFINE_OPERATOR_INSTR5(f_insn_call_indirect_vtable_blah, INSN_CCF);

// allocates address (1) with size (2)
DEFINE_OPERATOR_INSTR2(f_insn_call_alloc_bytearray, INSN_CBA);

// copy data to address (1) from address (2) with size (3)
DEFINE_OPERATOR_INSTR3(f_insn_call_copy_bytearray, INSN_BAC);

// loads value (1) from address (2) with offset (3), value is of type (4)
DEFINE_OPERATOR_INSTR4(f_insn_load_elem,            INSN_LBA);

// store ptr (1) + offset (2) = value (3)
DEFINE_OPERATOR_INSTR3(f_insn_store_elem,           INSN_SBA);

// increases the hit count for a given id (1)
DEFINE_OPERATOR_INSTR1(f_insn_hit,                  INSN_HIT);

// tests the hit count against the supplied ceiling (3) for a given id (2) and places the result in (1)
DEFINE_OPERATOR_INSTR3(f_insn_hot,                  INSN_HOT);

static VALUE f_insn_label(VALUE self, VALUE label_v)
{
   LabelSelf *label;
   Data_Get_Struct(label_v, LabelSelf, label);
   append_insn(insn, {
      instr->opcode = INSN_NOP;
      label->idx = func->instruction_idx;
      instr->num_vals = 0;
   });
   return Qnil;
}

static VALUE f_compile(VALUE self)
{
   dbg("compiling...\n");
   return Qnil;
}

typedef struct {
   VALUE params;
   VALUE next_function;
} Dispatch;

static Dispatch* exec_func(VALUE self, VALUE params);

// dispatcher
static VALUE f_apply(VALUE self, VALUE params)
{
   Dispatch *first_dispatch, *d;
   first_dispatch = ALLOC(Dispatch);
   first_dispatch->params        = params;
   first_dispatch->next_function = self;
   d = first_dispatch;
   for ( ;; ) {
      if (!NIL_P(d->next_function)) {
         dbg("dispatching to:");
#if DEBUG
         if (debug_on) {
            rb_funcall(d->next_function, rb_intern("display"), 0);
         }
#endif
         dbg("\n");
         Dispatch *d_new = exec_func(d->next_function, d->params);
         free(d);
         d = d_new;
      } else {
         return d->params;
      }
   }
   return Qnil;
}

#include "/tmp/insns.out.c"

static VALUE f_lock(VALUE self)
{
   // lock on
   if (rb_block_given_p()) {
      rb_yield(rb_ary_new());
   }
   // lock off
   return Qnil;
}

static VALUE addr2func(VALUE klass, VALUE addr)
{
   return *((VALUE*)NUM2UINT(addr));
}

static VALUE func2addr(VALUE klass, VALUE func)
{
   VALUE *value_ptr;
   value_ptr    = ALLOC(VALUE);
   (*value_ptr) = func;
   return UINT2NUM((int)value_ptr);
}

static VALUE ptr2string(VALUE klass, VALUE ptr, VALUE len)
{
   return rb_str_new((const char *)NUM2UINT(ptr), NUM2INT(len));
}

static VALUE stringpoke(VALUE klass, VALUE ptr, VALUE new_str, VALUE len)
{
   memcpy((char *)NUM2UINT(ptr), RSTRING_PTR(new_str), NUM2INT(len));
   return Qnil;
}

static VALUE bytearray2ptr(VALUE klass, VALUE _str)
{
   VALUE str = StringValue(_str);
   int *new_str = malloc(4 * RSTRING_LEN(str));
   memcpy(new_str, RSTRING_PTR(str), RSTRING_LEN(str));
   return INT2NUM((int)new_str);
}

static VALUE string2ptr(VALUE klass, VALUE _str)
{
   VALUE str = StringValue(_str);
   int *new_str = malloc(4 * ((1 + RSTRING_LEN(str)) * 2)), *dst = new_str;
   int pos;
   *(dst++) = RSTRING_LEN(str);
   *(dst++) = 2;
   for (pos = 0; pos < RSTRING_LEN(str); pos++) {
      *(dst++) = (int)RSTRING_PTR(str)[pos];
      *(dst++) = 2;
   }
   return INT2NUM((int)new_str);
}

VALUE cContext;
VALUE cFunction;
VALUE cValue;
VALUE cLabel;

void Init_nanovm() {
   g_int_sym_id       = rb_intern("int");
   g_int_sym_void_ptr = rb_intern("void_ptr");
   g_ptr_sym_id       = rb_intern("ptr");
   g_call_intern      = rb_intern("call");

   g_const = rb_intern("const");
   g_local = rb_intern("local");
   g_reg   = rb_intern("reg");
   g_param = rb_intern("param");

   cContext  = rb_define_class("Context", rb_cObject);
   rb_define_singleton_method(cContext, "new", c_new, 0);
   rb_define_singleton_method(cContext, "debug=", c_s_debug, 1);
   rb_define_method(cContext, "initialize", c_init, 0);

   cFunction = rb_define_class("Function", rb_cObject);
   rb_define_singleton_method(cFunction, "new", f_new, 1);
   rb_define_method(cFunction, "initialize", f_init, 1);
   rb_define_method(cFunction, "lock", f_lock, 0);
   rb_define_method(cFunction, "pos", f_pos, 0);
   rb_define_method(cFunction, "pos=", f_pos_set, 1);
   rb_define_method(cFunction, "metadata", f_metadata, 0);
   rb_define_method(cFunction, "metadata=", f_metadata_set, 1);
   rb_define_method(cFunction, "size", f_size, 0);
   rb_define_method(cFunction, "instructions_executed", f_instructions_executed, 0);
   rb_define_method(cFunction, "instr", f_instr, 0);
   rb_define_method(cFunction, "instr_comment", f_instr_comment, 0);
   rb_define_method(cFunction, "create_with_prototype", f_create_with_prototype, 2);
   rb_define_method(cFunction, "create_local", f_create_local, 2);
   rb_define_method(cFunction, "fill_value_with_constant", f_fill_value_with_constant, 3);
   rb_define_method(cFunction, "fill_value_with_param", f_fill_value_with_param, 2);
   rb_define_method(cFunction, "insn_add", f_insn_add, 3);
   rb_define_method(cFunction, "insn_sub", f_insn_sub, 3);
   rb_define_method(cFunction, "insn_mul", f_insn_mul, 3);
   rb_define_method(cFunction, "insn_div", f_insn_div, 3);
   rb_define_method(cFunction, "insn_rem", f_insn_rem, 3);
   rb_define_method(cFunction, "insn_lt",  f_insn_lt,  3);
   rb_define_method(cFunction, "insn_gt",  f_insn_gt,  3);
   rb_define_method(cFunction, "insn_return", f_insn_return, 1);
   rb_define_method(cFunction, "insn_label", f_insn_label, 1);
   rb_define_method(cFunction, "insn_eq", f_insn_eq, 3);
   rb_define_method(cFunction, "insn_ne", f_insn_ne, 3);
   rb_define_method(cFunction, "insn_branch", f_insn_branch, 1);
   rb_define_method(cFunction, "insn_branch_if", f_insn_branch_if, 2);
   rb_define_method(cFunction, "insn_branch_if_not", f_insn_branch_if_not, 2);
   rb_define_method(cFunction, "param_bindings", f_param_bindings, 0);
   rb_define_method(cFunction, "insn_hit", f_insn_hit, 1);
   rb_define_method(cFunction, "insn_hit_test", f_insn_hot, 3);
   rb_define_method(cFunction, "insn_call_print_int", f_insn_call_print_int, 1);
   rb_define_method(cFunction, "insn_call_alloc_bytearray", f_insn_call_alloc_bytearray, 2);
   rb_define_method(cFunction, "insn_call_copy_bytearray", f_insn_call_copy_bytearray, 3);
   rb_define_method(cFunction, "insn_call_data_inspect", f_insn_call_data_inspect, 4);
   rb_define_method(cFunction, "insn_call_build_function", f_insn_call_build_function, 5);
   rb_define_method(cFunction, "insn_call_indirect_vtable_blah", f_insn_call_indirect_vtable_blah, 5);
   rb_define_method(cFunction, "insn_load_elem", f_insn_load_elem, 4);
   rb_define_method(cFunction, "insn_store_elem", f_insn_store_elem, 3);
   rb_define_method(cFunction, "insn_store", f_insn_store, 2);
   rb_define_method(cFunction, "profile_hash", f_profile_hash, 0);
   rb_define_method(cFunction, "compile", f_compile, 0);
   rb_define_method(cFunction, "apply", f_apply, 1);

   cValue = rb_define_class("Value", rb_cObject);
   rb_define_singleton_method(cValue, "new", v_new, 0);
   rb_define_method(cValue, "initialize", v_init, 0);
   rb_define_method(cValue, "as_int", v_as_int, 0);
   rb_define_method(cValue, "as_obj", v_as_obj, 0);
   rb_define_method(cValue, "type", v_type, 0);
   rb_define_singleton_method(cValue, "ptr2string", ptr2string, 2);
   rb_define_singleton_method(cValue, "addr2func", addr2func, 1);
   rb_define_singleton_method(cValue, "func2addr", func2addr, 1);
   rb_define_singleton_method(cValue, "stringpoke", stringpoke, 3);
   rb_define_singleton_method(cValue, "string2ptr", string2ptr, 1);
   rb_define_singleton_method(cValue, "bytearray2ptr", bytearray2ptr, 1);

   cLabel = rb_define_class("Label", rb_cObject);
   rb_define_singleton_method(cLabel, "new", l_new, 0);
   rb_define_method(cLabel, "jump_pos", l_jump_pos, 0);
   rb_define_method(cLabel, "initialize", l_init, 0);
}
