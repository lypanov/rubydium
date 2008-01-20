#include <stdio.h>
#include <ruby.h>
#include <jit/jit.h>

#include "ruby.h"

#define NONNULL(val)                \
   if (val == NULL) {               \
      rb_bug("got a null!!!!");     \
      exit(1);                      \
   }

// #define DEBUG

VALUE mLibJit;
VALUE cContext;

typedef struct {
   jit_context_t context;
} ContextSelf;

static VALUE t_new(VALUE klass)
{
   VALUE argv[0];
   VALUE bul;
   ContextSelf *bt;
   bt = ALLOC(ContextSelf);
   bul = Data_Wrap_Struct(klass, 0, free, bt);
   rb_obj_call_init(bul, 0, argv);
   return bul;
}

static VALUE t_init(VALUE self)
{
   ContextSelf *bt;
   Data_Get_Struct(self, ContextSelf, bt);
	bt->context = jit_context_create();
   return self;
}

VALUE cFunction;

typedef struct {
   jit_function_t function;
} FunctionSelf;

static VALUE f_new(VALUE klass, VALUE context)
{
   VALUE bul;
   FunctionSelf *bt;
   bt = ALLOC(FunctionSelf);
   bul = Data_Wrap_Struct(klass, 0, free, bt);
   VALUE argv[1];
   argv[0] = context;
   rb_obj_call_init(bul, 1, argv);
   return bul;
}

static VALUE f_init(VALUE self, VALUE context)
{
   rb_iv_set(self, "@context", context);
   return self;
}

VALUE cValue;

typedef struct {
   // per default a jit_value_t is a temp value
   jit_value_t value;
} ValueSelf;

static VALUE v_new(VALUE klass)
{
   VALUE bul;
   ValueSelf *bt;
   bt = ALLOC(ValueSelf);
#ifdef DEBUG
   printf("allocating new value - %p\n", bt);
#endif
   bul = Data_Wrap_Struct(klass, 0, free, bt);
   VALUE argv[0];
   rb_obj_call_init(bul, 0, argv);
   return bul;
}

static VALUE v_init(VALUE self)
{
   return self;
}

VALUE cLabel;

typedef struct {
   jit_label_t label;
} LabelSelf;

static VALUE l_new(VALUE klass)
{
   VALUE bul;
   LabelSelf *bt;
   bt = ALLOC(LabelSelf);
   bul = Data_Wrap_Struct(klass, 0, free, bt);
   VALUE argv[0];
   rb_obj_call_init(bul, 0, argv);
   return bul;
}

static VALUE l_init(VALUE self)
{
   LabelSelf *lt;
   Data_Get_Struct(self, LabelSelf, lt);
   lt->label = jit_label_undefined;
   return self;
}

static VALUE f_lock(VALUE self)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

   VALUE context = rb_iv_get(self, "@context");
   ContextSelf *bt;
   Data_Get_Struct(context, ContextSelf, bt);

	jit_context_build_start(bt->context);

   if (rb_block_given_p()) {
      rb_yield(rb_ary_new());
   }

	jit_context_build_end(bt->context);

   return Qnil;
}

static jit_type_t *sitp = 0;
static jit_type_t *bytearraytype = 0;

#define INCREF 1

static jit_type_t id2jit_type(ID id) {
   ID int_sym_id = rb_intern("int");
   ID int_sym_void_ptr = rb_intern("void_ptr");
   ID int_rmval = rb_intern("rmval");
   ID int_bytearray = rb_intern("bytearray");
   if (id == int_sym_id)
	   return jit_type_int;
   if (id == int_sym_void_ptr)
	   return jit_type_void_ptr;
   if (!sitp) {
      jit_type_t fields[2];
      fields[0] = jit_type_int;
      fields[1] = jit_type_int;
      sitp = ALLOC(jit_type_t);
      *sitp = jit_type_create_struct(fields, 2, INCREF);
   }
   if (!bytearraytype) {
      bytearraytype = ALLOC(jit_type_t);
      *bytearraytype = jit_type_create_pointer(jit_type_ubyte, INCREF);
   }
   if (id == int_rmval)
      return *sitp;
   if (id == int_bytearray)
      return *bytearraytype;
   rb_bug("wha?");
}

static VALUE t_get_struct_offset(VALUE self, VALUE typev, VALUE field_index)
{
   jit_nuint offs = jit_type_get_offset(id2jit_type(SYM2ID(typev)), NUM2UINT(field_index));
   return INT2NUM(offs);
}

static jit_type_t gen_prototype(VALUE return_type, VALUE prototype) 
{
	jit_type_t *params = ALLOC_N(jit_type_t, RARRAY(prototype)->len);
   long c;
   for (c = 0; c < RARRAY(prototype)->len; c++) {
      ID id = SYM2ID(rb_ary_entry(prototype, c));
	   params[c] = id2jit_type(id);
   }

	return jit_type_create_signature
		      (jit_abi_cdecl, id2jit_type(SYM2ID(return_type)), params, RARRAY(prototype)->len, INCREF);
}

static VALUE f_create_with_prototype(VALUE self, VALUE return_type, VALUE prototype)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

   VALUE context = rb_iv_get(self, "@context");
   ContextSelf *bt;
   Data_Get_Struct(context, ContextSelf, bt);

   rb_iv_set(self, "@return_type", return_type);
   rb_iv_set(self, "@prototype", prototype);

   jit_type_t signature = gen_prototype(return_type, prototype);
	ft->function = jit_function_create(bt->context, signature);
   NONNULL(ft->function);

   return Qnil;
}

#ifdef DEBUG
#define UNWRAP_JIT_VALUE(var, ptr) { \
   ValueSelf *var##v_p; \
   Data_Get_Struct(var, ValueSelf, var##v_p); \
   ptr = &var##v_p->value; \
   printf("%s: unwrapping jit value %s at address %p\n", __FUNCTION__, #var, ptr); }
#else
#define UNWRAP_JIT_VALUE(var, ptr) { \
   ValueSelf *var##v_p; \
   Data_Get_Struct(var, ValueSelf, var##v_p); \
   ptr = &var##v_p->value; }
#endif

#define UNWRAP_JIT_LABEL(var, ptr) { \
   LabelSelf *var##v_p; \
   Data_Get_Struct(var, LabelSelf, var##v_p); \
   ptr = &var##v_p->label; }


static VALUE f_fill_value_with_param(VALUE self, VALUE rvalue, VALUE n)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

   jit_value_t *value;

   UNWRAP_JIT_VALUE(rvalue, value);
   *value = jit_value_get_param(ft->function, NUM2INT(n));

   return Qnil;
}

static void data_inspect_callback(jit_int value1, jit_int value2, jit_int value3, jit_int value4)
{
#ifdef DEBUG
   printf("CALLBACK my_data_inspect %d, %d, %d, %d\n", value1, value2, value3, value4);
#endif
   rb_funcall(rb_mKernel, rb_intern("my_data_inspect"), 4, 
              INT2FIX((unsigned int)value1), INT2FIX((unsigned int)value2), 
              INT2FIX((unsigned int)value3), INT2FIX((unsigned int)value4));
}

static VALUE ptr2string(VALUE klass, VALUE ptr, VALUE len)
{
   return rb_str_new((const char *)NUM2UINT(ptr), NUM2INT(len));
}

static void* build_function_callback(jit_int value, jit_int value2, jit_int value3)
{
#ifdef DEBUG
   printf("CALLBACK my_build_function %d, %d, %d\n", value, value2, value3);
#endif
   VALUE ftv = rb_funcall(rb_mKernel, rb_intern("my_build_function"), 3, INT2NUM((long)value), INT2NUM((long)value2), INT2NUM((long)value3));
   FunctionSelf *ft;
   Data_Get_Struct(ftv, FunctionSelf, ft);
   void *func_ptr = jit_function_to_vtable_pointer(ft->function);
   return func_ptr;
}

static void* dpas_alloc_bytearray(jit_int size)
{
   void *ptr = (void *) jit_malloc((int)size);
#ifdef DEBUG
   printf("allocated pointer %p\n", ptr);
#endif
   printf("allocated pointer %d\n", ptr);
   return ptr;
}

static void* dpas_realloc_bytearray(void *addr, jit_int size)
{
   void *ptr = (void*) jit_realloc(addr, (int)size);
#ifdef DEBUG
   printf("trying to reallocate %p to %d bytes it became %p!\n", addr, size, ptr);
#endif
   return ptr;
}

static void dpas_write_int(jit_int value)
{
	char *my_string;
   asprintf(&my_string, "%ld\n", (long)value);
   rb_funcall(rb_mKernel, rb_intern("my_callback"), 1, rb_str_new2(my_string));
}

static void dpas_write_char(jit_int value)
{
	char *my_string;
   asprintf(&my_string, "%c", (long)value);
   rb_funcall(rb_mKernel, rb_intern("my_callback"), 1, rb_str_new2(my_string));
}

static jit_value_t call_builtin
	(jit_function_t func, const char *name, void *native_func,
	 jit_type_t arg1_type, jit_value_t value1,
	 jit_type_t arg2_type, jit_value_t value2,
	 jit_type_t arg3_type, jit_value_t value3,
	 jit_type_t arg4_type, jit_value_t value4,
	 jit_type_t return_type)
{
	jit_type_t signature;
	jit_type_t arg_types[4];
	jit_value_t args[4];
	int num_args = 0;
	if(arg1_type)
	{
		args[num_args] = jit_insn_convert(func, value1, arg1_type, 0);
		if(!(args[num_args]))
		{
         rb_bug("oom!");
		}
		arg_types[num_args] = arg1_type;
		++num_args;
	}
	if(arg2_type)
	{
		args[num_args] = jit_insn_convert(func, value2, arg2_type, 0);
		if(!(args[num_args]))
		{
         rb_bug("oom!");
		}
		arg_types[num_args] = arg2_type;
		++num_args;
	}
	if(arg3_type)
	{
		args[num_args] = jit_insn_convert(func, value3, arg3_type, 0);
		if(!(args[num_args]))
		{
         rb_bug("oom!");
		}
		arg_types[num_args] = arg3_type;
		++num_args;
	}
	if(arg4_type)
	{
		args[num_args] = jit_insn_convert(func, value4, arg4_type, 0);
		if(!(args[num_args]))
		{
         rb_bug("oom!");
		}
		arg_types[num_args] = arg4_type;
		++num_args;
	}
	signature = jit_type_create_signature
		(jit_abi_cdecl, return_type, arg_types, num_args, 1);
	if(!signature)
	{
      rb_bug("oom!");
	}
	value1 = jit_insn_call_native(func, name, native_func, signature,
							      args, num_args, JIT_CALL_NOTHROW);
	if(!value1)
	{
      rb_bug("oom!");
	}
	jit_type_free(signature);
	return value1;
}

static void call_write
	(jit_function_t func, const char *name, void *native_func,
	 jit_type_t arg1_type, jit_value_t value1)
{
	call_builtin(func, name, native_func, arg1_type,
				    value1, 0, 0, 0, 0, 0, 0, jit_type_void);
}

static VALUE f_insn_label(VALUE self, VALUE labelv)
{
   jit_label_t *label;
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

   UNWRAP_JIT_LABEL(labelv, label);
   jit_insn_label(ft->function, label);
   
   return Qnil;
}

static VALUE f_insn_branch_if(VALUE self, VALUE valuev, VALUE labelv)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

   jit_label_t *label;
   UNWRAP_JIT_LABEL(labelv, label);
   jit_value_t *value;
   UNWRAP_JIT_VALUE(valuev, value);

   jit_insn_branch_if(ft->function, *value, label);
   
   return Qnil;
}
static VALUE f_insn_branch_if_not(VALUE self, VALUE valuev, VALUE labelv)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

   jit_label_t *label;
   UNWRAP_JIT_LABEL(labelv, label);
   jit_value_t *value;
   UNWRAP_JIT_VALUE(valuev, value);

   jit_insn_branch_if_not(ft->function, *value, label);
   
   return Qnil;
}

static VALUE f_insn_branch(VALUE self, VALUE labelv)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

   jit_label_t *label;
   UNWRAP_JIT_LABEL(labelv, label);

   jit_insn_branch(ft->function, label);
   
   return Qnil;
}

static VALUE f_insn_ne(VALUE self, VALUE destv, VALUE param1v, VALUE param2v)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *dest, *param1, *param2;
   UNWRAP_JIT_VALUE(destv,  dest);
   UNWRAP_JIT_VALUE(param1v, param1);
   UNWRAP_JIT_VALUE(param2v, param2);

	*dest = jit_insn_ne(ft->function, *param1, *param2);

   return Qnil;
}

static VALUE f_insn_eq(VALUE self, VALUE destv, VALUE param1v, VALUE param2v)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *dest, *param1, *param2;
   UNWRAP_JIT_VALUE(destv,  dest);
   UNWRAP_JIT_VALUE(param1v, param1);
   UNWRAP_JIT_VALUE(param2v, param2);

	*dest = jit_insn_eq(ft->function, *param1, *param2);

   return Qnil;
}

static VALUE f_insn_gt(VALUE self, VALUE destv, VALUE param1v, VALUE param2v)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *dest, *param1, *param2;
   UNWRAP_JIT_VALUE(destv,  dest);
   UNWRAP_JIT_VALUE(param1v, param1);
   UNWRAP_JIT_VALUE(param2v, param2);

	*dest = jit_insn_gt(ft->function, *param1, *param2);

   return Qnil;
}

static VALUE f_insn_lt(VALUE self, VALUE destv, VALUE param1v, VALUE param2v)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *dest, *param1, *param2;
   UNWRAP_JIT_VALUE(destv,  dest);
   UNWRAP_JIT_VALUE(param1v, param1);
   UNWRAP_JIT_VALUE(param2v, param2);

	*dest = jit_insn_lt(ft->function, *param1, *param2);

   return Qnil;
}

static VALUE f_insn_mul(VALUE self, VALUE temp1v, VALUE param1v, VALUE param2v)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *temp1, *param1, *param2;
   UNWRAP_JIT_VALUE(temp1v,  temp1);
   UNWRAP_JIT_VALUE(param1v, param1);
   UNWRAP_JIT_VALUE(param2v, param2);

	*temp1 = jit_insn_mul(ft->function, *param1, *param2);

   return Qnil;
}

static VALUE f_insn_div(VALUE self, VALUE temp1v, VALUE param1v, VALUE param2v)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *temp1, *param1, *param2;
   UNWRAP_JIT_VALUE(temp1v,  temp1);
   UNWRAP_JIT_VALUE(param1v, param1);
   UNWRAP_JIT_VALUE(param2v, param2);

	*temp1 = jit_insn_div(ft->function, *param1, *param2);

   return Qnil;
}

static VALUE f_insn_rem(VALUE self, VALUE temp1v, VALUE param1v, VALUE param2v)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *temp1, *param1, *param2;
   UNWRAP_JIT_VALUE(temp1v,  temp1);
   UNWRAP_JIT_VALUE(param1v, param1);
   UNWRAP_JIT_VALUE(param2v, param2);

	*temp1 = jit_insn_rem(ft->function, *param1, *param2);

   return Qnil;
}

static VALUE f_insn_call_data_inspect(VALUE self, VALUE val1v, VALUE val2v, VALUE val3v, VALUE val4v)
{
   printf("CALLBACK!!! my_data_inspect\n");

   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *val1;
   UNWRAP_JIT_VALUE(val1v, val1);

	jit_value_t *val2;
   UNWRAP_JIT_VALUE(val2v, val2);

	jit_value_t *val3;
   UNWRAP_JIT_VALUE(val3v, val3);

	jit_value_t *val4;
   UNWRAP_JIT_VALUE(val4v, val4);

	call_builtin(ft->function, "data_inspect_callback", (void *)data_inspect_callback, 
                jit_type_void_ptr, *val1, jit_type_void_ptr, *val2,
                jit_type_void_ptr, *val3, jit_type_void_ptr, *val4,
                jit_type_void);

   return Qnil;
}

static VALUE f_insn_call_build_function(VALUE self, VALUE retv, VALUE valv, VALUE val2v, VALUE val3v)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *val;
   UNWRAP_JIT_VALUE(valv, val);

	jit_value_t *val2;
   UNWRAP_JIT_VALUE(val2v, val2);

	jit_value_t *val3;
   UNWRAP_JIT_VALUE(val3v, val3);

	jit_value_t *ret;
   UNWRAP_JIT_VALUE(retv, ret);

	*ret = call_builtin(ft->function, "build_function_callback", (void *)build_function_callback, 
                       jit_type_int, *val, jit_type_int, *val2, jit_type_int, *val3, 0, 0, jit_type_void_ptr);

   return Qnil;
}

static void ** blub(VALUE prototype, VALUE params)
{
	void **args = ALLOC_N(void*, RARRAY(prototype)->len);
   long c;
   ID int_sym_id = rb_intern("int");
   for (c = 0; c < RARRAY(prototype)->len; c++) {
      ID id = SYM2ID(rb_ary_entry(prototype, c));
      if (id == int_sym_id) {
         jit_int *arg = ALLOC_N(jit_int, 1);
         (*arg) = NUM2INT(rb_ary_entry(params, c));
         args[c] = arg;
         continue;
      }
      rb_bug("non handled type in parameter list!");
   }
   return args;
}


static jit_value_t* blub2(VALUE params)
{
	jit_value_t *args = ALLOC_N(jit_value_t, RARRAY(params)->len);
   long c;
   for (c = 0; c < RARRAY(params)->len; c++) {
      VALUE valuev = rb_ary_entry(params, c);
      jit_value_t *value;
      UNWRAP_JIT_VALUE(valuev, value);
      args[c] = *value;
   }
   return args;
}

static VALUE f_insn_call_indirect_vtable_blah(VALUE self, VALUE retv, VALUE ptrv, VALUE return_type, VALUE prototype, VALUE params)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *ptr;
   UNWRAP_JIT_VALUE(ptrv, ptr);

	jit_value_t *ret;
   UNWRAP_JIT_VALUE(retv, ret);

   jit_type_t signature = gen_prototype(return_type, prototype);
   *ret = jit_insn_call_indirect_vtable(ft->function, *ptr, signature, blub2(params), RARRAY(params)->len, 0);

   return Qnil;
}

static VALUE f_insn_call_indirect_vtable_blah_tail(VALUE self, VALUE retv, VALUE ptrv, VALUE return_type, VALUE prototype, VALUE params)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *ptr;
   UNWRAP_JIT_VALUE(ptrv, ptr);

	jit_value_t *ret;
   UNWRAP_JIT_VALUE(retv, ret);

   jit_type_t signature = gen_prototype(return_type, prototype);
   *ret = jit_insn_call_indirect_vtable(ft->function, *ptr, signature, blub2(params), RARRAY(params)->len, JIT_CALL_TAIL);

   return Qnil;
}

static VALUE f_insn_call_print_int(VALUE self, VALUE valv)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *val;
   UNWRAP_JIT_VALUE(valv, val);

	call_write(ft->function, "dpas_write_int", (void *)dpas_write_int, jit_type_int, *val);

   return Qnil;
}

static VALUE f_insn_call_alloc_bytearray(VALUE self, VALUE retv, VALUE valv)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *val;
   UNWRAP_JIT_VALUE(valv, val);

	jit_value_t *ret;
   UNWRAP_JIT_VALUE(retv, ret);

	*ret = call_builtin(ft->function, "dpas_alloc_bytearray", (void *)dpas_alloc_bytearray, 
                       jit_type_int, *val, 0, 0, 0, 0, 0, 0,jit_type_void_ptr);

   return Qnil;
}

static VALUE f_insn_call_realloc_bytearray(VALUE self, VALUE retv, VALUE addrv, VALUE sizev)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *size;
   UNWRAP_JIT_VALUE(sizev, size);

	jit_value_t *addr;
   UNWRAP_JIT_VALUE(addrv, addr);

	jit_value_t *ret;
   UNWRAP_JIT_VALUE(retv, ret);

	*ret = call_builtin(ft->function, "dpas_realloc_bytearray", (void *)dpas_realloc_bytearray, 
                       jit_type_void_ptr, *addr, jit_type_int, *size, 0, 0, 0, 0, jit_type_void_ptr);

   return Qnil;
}

static VALUE f_insn_call_print_char(VALUE self, VALUE valv)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *val;
   UNWRAP_JIT_VALUE(valv, val);

	call_write(ft->function, "dpas_write_char", (void *)dpas_write_char, jit_type_int, *val);

   return Qnil;
}

static VALUE f_insn_dup(VALUE self, VALUE tempv, VALUE paramv)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *temp, *param;
   UNWRAP_JIT_VALUE(tempv,  temp);
   UNWRAP_JIT_VALUE(paramv, param);

	*temp = jit_insn_dup(ft->function, *param);

   return Qnil;
}

static VALUE f_insn_to_not_bool(VALUE self, VALUE tempv, VALUE paramv)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *temp, *param;
   UNWRAP_JIT_VALUE(tempv,  temp);
   UNWRAP_JIT_VALUE(paramv, param);

	*temp = jit_insn_to_not_bool(ft->function, *param);

   return Qnil;
}

static VALUE f_insn_sub(VALUE self, VALUE temp2v, VALUE temp1v, VALUE param3v)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *temp1, *temp2, *param3;
   UNWRAP_JIT_VALUE(temp1v,  temp1);
   UNWRAP_JIT_VALUE(temp2v,  temp2);
   UNWRAP_JIT_VALUE(param3v, param3);

	*temp2 = jit_insn_sub(ft->function, *temp1, *param3);

   return Qnil;
}

static VALUE f_insn_add(VALUE self, VALUE temp2v, VALUE temp1v, VALUE param3v)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

	jit_value_t *temp1, *temp2, *param3;
   UNWRAP_JIT_VALUE(temp1v,  temp1);
   UNWRAP_JIT_VALUE(temp2v,  temp2);
   UNWRAP_JIT_VALUE(param3v, param3);

	*temp2 = jit_insn_add(ft->function, *temp1, *param3);

   return Qnil;
}

static VALUE f_fill_value_with_constant(VALUE self, VALUE destv, VALUE typev, VALUE val)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

   jit_value_t *dest;
   UNWRAP_JIT_VALUE(destv, dest);

   ID int_sym_id = rb_intern("int");
   if (SYM2ID(typev) == int_sym_id) {
// printf("constant: %d\n", NUM2INT(val));
      *dest = jit_value_create_nint_constant(ft->function, id2jit_type(SYM2ID(typev)), NUM2INT(val));
      return Qnil;
   }

   rb_bug("non handled type in parameter list!");
   return Qnil;
}

static VALUE f_create_local(VALUE self, VALUE localv, VALUE typev)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

   jit_value_t *local;
   UNWRAP_JIT_VALUE(localv, local);

   *local = jit_value_create(ft->function, id2jit_type(SYM2ID(typev)));

   return Qnil;
}

static VALUE f_insn_return(VALUE self, VALUE retv)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

   jit_value_t *ret;
   UNWRAP_JIT_VALUE(retv, ret);

	jit_insn_return(ft->function, *ret);

   return Qnil;
}

static VALUE f_insn_address_of(VALUE self, VALUE addrv, VALUE value1v)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

   jit_value_t *addr;
   UNWRAP_JIT_VALUE(addrv, addr);
   jit_value_t *value1;
   UNWRAP_JIT_VALUE(value1v, value1);

	*addr = jit_insn_address_of(ft->function, *value1);

   return Qnil;
}

static VALUE f_insn_store(VALUE self, VALUE destv, VALUE valuev)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

   jit_value_t *dest;
   UNWRAP_JIT_VALUE(destv, dest);
   jit_value_t *value;
   UNWRAP_JIT_VALUE(valuev, value);

	if (!jit_insn_store(ft->function, *dest, *value))
      rb_bug("oops!");
   
   return Qnil;
}

static VALUE f_insn_store_relative(VALUE self, VALUE addrv, VALUE offset, VALUE valuev)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

   jit_value_t *addr;
   UNWRAP_JIT_VALUE(addrv, addr);
   jit_value_t *value;
   UNWRAP_JIT_VALUE(valuev, value);

	if (!jit_insn_store_relative(ft->function, *addr, NUM2INT(offset), *value))
      rb_bug("oops!");
   
   return Qnil;
}

static VALUE f_insn_store_elem(VALUE self, VALUE addrv, VALUE offsv, VALUE valuev)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

   jit_value_t *addr;
   UNWRAP_JIT_VALUE(addrv, addr);
   jit_value_t *value;
   UNWRAP_JIT_VALUE(valuev, value);
   jit_value_t *offs;
   UNWRAP_JIT_VALUE(offsv, offs);

	if (!jit_insn_store_elem(ft->function, *addr, *offs, *value))
      rb_bug("oops!");
   
   return Qnil;
}

static VALUE f_insn_load_relative(VALUE self, VALUE retv, VALUE addrv, VALUE offset, VALUE typev)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

   jit_value_t *ret;
   UNWRAP_JIT_VALUE(retv, ret);
   jit_value_t *addr;
   UNWRAP_JIT_VALUE(addrv, addr);

	*ret = jit_insn_load_relative(ft->function, *addr, NUM2INT(offset), id2jit_type(SYM2ID(typev)));
   
   return Qnil;
}

static VALUE f_insn_load_elem(VALUE self, VALUE retv, VALUE addrv, VALUE offsv, VALUE typev)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);

   jit_value_t *ret;
   UNWRAP_JIT_VALUE(retv, ret);
   jit_value_t *addr;
   UNWRAP_JIT_VALUE(addrv, addr);
   jit_value_t *offs;
   UNWRAP_JIT_VALUE(offsv, offs);

	*ret = jit_insn_load_elem(ft->function, *addr, *offs, id2jit_type(SYM2ID(typev)));
   
   return Qnil;
}

static VALUE f_compile(VALUE self)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);
#ifdef DEBUG
   jit_dump_function(stderr, ft->function, "blub");
#endif
	jit_function_compile(ft->function);
#ifdef DEBUG
   jit_dump_function(stderr, ft->function, "blub");
#endif
   return Qnil;
}

static VALUE f_apply(VALUE self, VALUE params)
{
   FunctionSelf *ft;
   Data_Get_Struct(self, FunctionSelf, ft);
	jit_int result;
   VALUE return_type = rb_iv_get(self, "@return_type");
   VALUE prototype = rb_iv_get(self, "@prototype");
	jit_function_apply(ft->function, blub(prototype, params), &result);
   ID int_sym_id = rb_intern("int");
   if (SYM2ID(return_type) == int_sym_id) {
	   printf("apply -> %d\n", (int)result);
      return Qnil;
   }
   rb_bug("non handled return type!");
   return Qnil;
}

static VALUE t_cleanup(VALUE self) {
   ContextSelf *bt;
   Data_Get_Struct(self, ContextSelf, bt);
	jit_context_destroy(bt->context);
   return Qnil;
}

void Init_libjit() {
   mLibJit = rb_define_module("LibJit");
   cContext = rb_define_class_under(mLibJit, "Context", rb_cObject);
   rb_define_singleton_method(cContext, "new", t_new, 0);
   rb_define_method(cContext, "initialize", t_init, 0);
   rb_define_method(cContext, "cleanup", t_cleanup, 0);
   rb_define_method(cContext, "get_struct_offset", t_get_struct_offset, 2);
   cFunction = rb_define_class_under(mLibJit, "Function", rb_cObject);
   rb_define_singleton_method(cFunction, "new", f_new, 1);
   rb_define_method(cFunction, "initialize", f_init, 1);
   rb_define_method(cFunction, "create_with_prototype", f_create_with_prototype, 2);
   rb_define_method(cFunction, "lock", f_lock, 0);
   rb_define_method(cFunction, "insn_mul", f_insn_mul, 3);
   rb_define_method(cFunction, "insn_div", f_insn_div, 3);
   rb_define_method(cFunction, "insn_rem", f_insn_rem, 3);
   rb_define_method(cFunction, "insn_call_print_int", f_insn_call_print_int, 1);
   rb_define_method(cFunction, "insn_call_print_char", f_insn_call_print_char, 1);
   rb_define_method(cFunction, "insn_call_build_function", f_insn_call_build_function, 4);
   rb_define_method(cFunction, "insn_call_data_inspect", f_insn_call_data_inspect, 4);
   rb_define_method(cFunction, "insn_call_indirect_vtable_blah", f_insn_call_indirect_vtable_blah, 5);
   rb_define_method(cFunction, "insn_call_indirect_vtable_blah_tail", f_insn_call_indirect_vtable_blah_tail, 5);
   rb_define_method(cFunction, "insn_call_alloc_bytearray", f_insn_call_alloc_bytearray, 2);
   rb_define_method(cFunction, "insn_call_realloc_bytearray", f_insn_call_realloc_bytearray, 3);
   rb_define_method(cFunction, "insn_add", f_insn_add, 3);
   rb_define_method(cFunction, "insn_sub", f_insn_sub, 3);
   rb_define_method(cFunction, "insn_dup", f_insn_dup, 2);
   rb_define_method(cFunction, "insn_to_not_bool", f_insn_to_not_bool, 2);
   rb_define_method(cFunction, "insn_ne", f_insn_ne, 3);
   rb_define_method(cFunction, "insn_eq", f_insn_eq, 3);
   rb_define_method(cFunction, "insn_gt", f_insn_gt, 3);
   rb_define_method(cFunction, "insn_lt", f_insn_lt, 3);
   rb_define_method(cFunction, "insn_return", f_insn_return, 1);
   rb_define_method(cFunction, "insn_label", f_insn_label, 1);
   rb_define_method(cFunction, "insn_branch_if_not", f_insn_branch_if_not, 2);
   rb_define_method(cFunction, "insn_branch_if", f_insn_branch_if, 2);
   rb_define_method(cFunction, "insn_branch", f_insn_branch, 1);
   rb_define_method(cFunction, "insn_address_of", f_insn_address_of, 2);
   rb_define_method(cFunction, "insn_store", f_insn_store, 2);
   rb_define_method(cFunction, "insn_store_relative", f_insn_store_relative, 3);
   rb_define_method(cFunction, "insn_store_elem", f_insn_store_elem, 3);
   rb_define_method(cFunction, "insn_load_relative", f_insn_load_relative, 4);
   rb_define_method(cFunction, "insn_load_elem", f_insn_load_elem, 4);
   rb_define_method(cFunction, "fill_value_with_param", f_fill_value_with_param, 2);
   rb_define_method(cFunction, "fill_value_with_constant", f_fill_value_with_constant, 3);
   rb_define_method(cFunction, "create_local", f_create_local, 2);
   rb_define_method(cFunction, "compile", f_compile, 0);
   rb_define_method(cFunction, "apply", f_apply, 1);
   cValue = rb_define_class_under(mLibJit, "Value", rb_cObject);
   rb_define_singleton_method(cValue, "new", v_new, 0);
   rb_define_singleton_method(cValue, "ptr2string", ptr2string, 2);
   rb_define_method(cValue, "initialize", v_init, 0);
   cLabel = rb_define_class_under(mLibJit, "Label", rb_cObject);
   rb_define_singleton_method(cLabel, "new", l_new, 0);
   rb_define_method(cLabel, "initialize", l_init, 0);
}
