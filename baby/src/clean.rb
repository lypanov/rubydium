require 'nanovm'
require '../nanovm/nano.rb'

$: << "../../ruby_parser-1.0.0/lib" << "../3rdparty/breakpoint"
require 'ruby_parser'
# require "rubygems"
# require 'parse_tree'

require 'debug-declarations.rb'
require 'misc.rb'
require 'bench.rb'

require 'pp'
require 'breakpoint'
require 'digest/md5'
require 'pstore'
require 'yaml/store.rb' # including this shaves a few seconds of testing, why?
require 'enumerator'

def pause
   STDIN.gets
end

Context.debug = $nanovm_debug

class ProfFuncWithMd

   def self.md_metadata func
      func.metadata = {}
   end

   def self.md_get_id func
      func.metadata[:path_range].first
   end

   def self.md_get_path_range func
      func.metadata[:path_range]
   end

   def self.md_set_path_range func, new_path_range
      func.metadata[:path_range] = new_path_range
   end

   def self.md_init_and_add_to_caller_map_and_return_size func, str
      func.metadata[:caller_map] ||= ([nil] * 8)
      func.metadata[:caller_map] << str
      func.metadata[:caller_map].size
   end

   def self.md_add_to_lookup_for_debug func, name
      func.metadata[:lookup_for] ||= []
      func.metadata[:lookup_for]  << [name]
   end

   def self.md_add_to_static_scope func, scope, scope_id, sym
      func.metadata[:used_scope_template] = scope
      func.metadata[:used_static_scopes] ||= []
      func.metadata[:used_static_scopes]  << [scope_id, sym]
   end

   def self.md_find_in_caller_map func, slow_id
      (func.metadata[:caller_map].index [:id, slow_id]) + 1
   end

   def self.md_set_next_id func, curr_id
      func.metadata[:next_id] = curr_id
   end

   def self.md_set_is_bouncer func
      func.metadata[:is_bouncer] = true
   end

   def self.md_add_assumption func, obj
      func.metadata[:assumptions] << obj
   end

   def self.md_add_to_static_continuation_points func, next_id
      func.metadata[:static_continuation_point] ||= []
      func.metadata[:static_continuation_point] << next_id
   end

   def self.md_add_to_bouncing_cont_points func, next_id
      func.metadata[:bouncing_continuation_point] ||= []
      func.metadata[:bouncing_continuation_point] << next_id
   end

   def self.md_made_scope func
      func.metadata[:made_scope] = true
   end

   def self.md_made_scope? func
      func.metadata[:made_scope]
   end

   def self.md_init_or_increase_bouncer_count func
      func.metadata[:func] ||= 0
      func.metadata[:func] += 1
   end
   
   def self.md_unset_made_scope func
      func.metadata.delete :made_scope
   end

   def self.md_init_init_func func
      func.metadata[:init_func] = []
   end

   def self.md_set_atom_main_label func, atom_main_label 
      func.metadata[:atom_main_label] = atom_main_label 
   end
   def self.md_get_statically_dispatches_to func 
      func.metadata[:statically_dispatches_to]
   end

   def self.md_get_static_continuation_point func
      func.metadata[:static_continuation_point]
   end

   def self.md_get_slow_dispatches func
      func.metadata[:slow_dispatch_to]
   end

   def self.md_set_last_hit_count func, count
      func.metadata[:last_hit_count] = count
   end

   def self.md_inc_rebuild_count func
      rebuild_count = func.metadata[:rebuild_count] || 0
      func.metadata[:rebuild_count] = rebuild_count + 1
   end

   def self.md_get_num_params func
      func.metadata[:num_params]
   end

   def self.md_get_prev_id func
      func.metadata[:prev_id]
   end

   def self.md_get_was_generated_by func
      func.metadata[:was_generated_by]
   end
   
   def self.md_get_creates_bouncer_to func
      func.metadata[:creates_bouncer_to]
   end

   def self.md_get_next_ids func
      func.metadata[:next_ids]
   end

   def self.md_has_slow_dispatches func
      func.metadata.has_key? :slow_dispatch_to
   end

   def self.md_get_next_id func
      func.metadata[:next_id]
   end

   def self.md_get_last_hit_count func
      func.metadata[:last_hit_count]
   end

   def self.md_get_assumptions func
      func.metadata[:assumptions]
   end

   def self.md_get_generated_by func
      func.metadata[:bouncer_generated_by]
   end

   def self.md_set_generated_by func, bouncer_generated_by
      func.metadata[:bouncer_generated_by] = bouncer_generated_by
   end

   def self.md_has_no_bouncer_generated_annotation func
      func.metadata[:bouncer_generated_by].nil?
   end

   def self.md_has_init_func func
      func.metadata.has_key?(:init_func)
   end

   def self.md_is_not_real? func
      (func.metadata[:assumptions].include? [:not_real])
   end

   def self.md_mark_not_real func
      func.metadata[:assumptions] << [:not_real]
   end

   def self.md_no_assumptions? func
      (func.metadata[:assumptions].empty?)
   end

   def self.md_not_all_static_lookups? func
      (func.metadata[:lookup_for] and !func.metadata[:lookup_for].empty?)
   end

   # currently no setter!
   def self.md_optimal_return? func
      (!func.metadata[:optimal_return].nil? and func.metadata[:optimal_return] == true)
   end

   def self.md_lookups func
      func.metadata[:lookup_for]
   end

   def self.md_atom_main_label func
      func.metadata[:atom_main_label]
   end

   def self.md_set_with_initial func, symbol, initial, &new_value
      func.metadata[symbol] ||= initial
      func.metadata[symbol] = (new_value.call func.metadata[symbol])
   end

   def self.md_force_data_inspect func
      func.metadata[:force_data_inspect] = true
   end

   def self.md_forced_data_inspect func
      func.metadata[:force_data_inspect]
   end

   def self.md_set_create_scope_template func, scope
      func.metadata[:create_scope_template] = scope
   end
   
   def self.metadata_filter notes
      notes.reject { |(a,b)| (a == :caller_map) }
   end

   def self.md_inspect notes
      (self.metadata_filter notes).inspect
   end

end

class ProfilingFunction < Function
   attr_accessor :mem_ctx
   def initialize *k
      @func = super *k
      @func
   end
   def inspect
      path_range = ProfFuncWithMd::md_get_path_range(@func).inspect
      "PFunction::[#{path_range}]- #{ProfFuncWithMd::md_inspect @func.metadata}>"
   end
   def self.record_hit func, str
      top_val = ProfFuncWithMd::md_init_and_add_to_caller_map_and_return_size func, str
      func.insn_hit NN::mk_constant(func, :int, top_val)
   end
   instance_methods.each {
      |meth|
      conditional = (meth =~ /insn_/ and meth != "insn_hit")
      if conditional
         define_method(meth) {
            |*args|
            fail "no mem_ctx!!!" unless mem_ctx
            appending_not_hacking = (@func.pos == @func.size)
            if appending_not_hacking and $profile
               ProfilingFunction.record_hit(@func, (caller[1..1].join ", "))
            end
            if appending_not_hacking and meth == "insn_call_indirect_vtable_blah"
               trace_stack_ptr = Value.new
               self.insn_load_elem trace_stack_ptr, mem_ctx.stack_mem, 
                  NN::mk_constant(self, :int, 7), :void_ptr
               trace_stack = RbStack.new self, trace_stack_ptr, :alt
               old_func_ptr, new_func_ptr = Value.new, Value.new
               self.insn_load_elem new_func_ptr, mem_ctx.stack_mem, 
                  NN::mk_constant(self, :int, 8), :void_ptr
               self.insn_load_elem old_func_ptr, mem_ctx.stack_mem, 
                  NN::mk_constant(self, :int, 9), :void_ptr
               trace_stack.push new_func_ptr, old_func_ptr
            end
            pos = @func.pos
            super(*args)
            return pos
         }
      end
   }
end

Annotation = Struct.new :type

   Unset = Class.new

   class TreeState
      attr_accessor :path, :sexp_elt, :curr_id
      def initialize crawler, path2anon_block, curr_id
         @crawler = crawler
         @curr_id = curr_id
         @path    = crawler.id2path curr_id
         @sexp_elt = crawler.find_path_sexp @path
         @anon_block = Unset
         @path2anon_block = path2anon_block 
      end
      def anon_block
         @anon_block = @path2anon_block[@path] if @anon_block == Unset
         @anon_block
      end
   end

if false # set to true if we want to test parsetree usage
   class Array
      def sexp_body
         return self[1..-1]
      end
   end
   def is_a_sexp? elt
      # complete hack!!!
      elt.is_a? Array and elt[0].is_a? Symbol
   end
   def s *foo
      return [*foo]
   end
else
   def is_a_sexp? elt
      elt.is_a? Sexp
   end
   class ParseTree
      def self.translate src
         RubyParser.new.parse(src)
      end
   end
end
class CodeTree
   attr_accessor :ast, :id2path_hash
   def initialize sexp
      @sexp         = ast_hacks sexp
      @id2path_hash = {}
      @associated   = {}
      preload_ast @sexp, []
      @id2path_hash[@id2path_hash.length] = []
   end
   def ast_hacks sexp
     insides = sexp.sexp_body.map { |elt| is_a_sexp?(elt) ? ast_hacks(elt) : elt }
     # turn blocks with > 2 children into [:block, child1, [:block, child2, child3]]
     if sexp.first == :block && sexp[1].first == :dasgn_curr
       # emulate legacy node, not produced by ParseTree and can probably be removed later on
       return s(:block, 
                s(:dasgn_curr_hacked, sexp[1][1], nil), 
                (ast_hacks s(:block, s(:dasgn_curr_hacked, *sexp[1][1..-1]), *sexp[2..-1])))
     elsif sexp.first == :block && sexp.length > 3 # when more than two elements in block
       return s(:block, insides[0], ast_hacks(s(:block, *sexp[2..-1])))
     elsif sexp.first == :scope
       return s(:scope, [], *insides)
     elsif sexp.first == :class
       return s(:class, s(:colon2, nil, sexp[1]), *insides[1..-1])
     elsif sexp.first == :while
       return s(:while, *insides[0..-2])
     elsif sexp.first == :defn
       blocks = sexp[2][1][2..-1]
       if blocks.length > 1
         blocks = [ast_hacks(s(:block, *blocks))]
       end
       return s(:defn_hacked, insides[0], sexp[2][1][1].sexp_body.to_a, *blocks)
     else
       return s(sexp.first, *insides)
     end
   end
   def self.find_subpaths path_list, subpath_root, inclusive = false
      bench("find_subpaths") {
         return path_list.find_all {
            |path|
            prefix = path.slice 0, subpath_root.length
            (path.length > subpath_root.length) \
        and (prefix === subpath_root)
         } + (inclusive ? [subpath_root] : [])
      }
   end
   def preload_ast sexp, path
      # puts "preload_ast: #{path.inspect}: #{ast.inspect}\n\t: #{sexp.inspect}"
      rest = (sexp.empty?) ? [] : sexp[1..-1]
      s_order_arr = rest.inject([]) { |oarr, elt| oarr << [elt, oarr.size]; oarr }
      s_order_arr << s_order_arr.slice!(0) if (sexp.first == :call)
      s_order_arr.each {
         |(inner_sexp, idx)|
         new_path = path + [idx]
         if inner_sexp.class.to_s =~ /(Sexp|Array)/
            preload_ast inner_sexp, new_path
            if (sexp.first == :call) and idx == 0 # push before the first param
               # FIXME - extract
               assoc_path = path + [-1]
               fail "already associated something with #{assoc_path.inspect}" if @associated.has_key? assoc_path
               @associated[assoc_path] = :push_block
               @id2path_hash[@id2path_hash.length] = assoc_path
            end
         end
         @id2path_hash[@id2path_hash.length] = new_path
      }
      if [:vcall,:fcall].include? sexp.first
         # FIXME - extract
         assoc_path = path + [-1]
         fail "already associated something with #{assoc_path.inspect}" if @associated.has_key? assoc_path
         @associated[assoc_path] = :push_block
         @id2path_hash[@id2path_hash.length] = assoc_path
      end
   end
   def path2id path
      @id2path_hash.index path
   end
   def id2path id
      @id2path_hash[id]
   end
   def find_path_sexp to_find, sexp = nil, path = nil
      # puts "sexp finding:#{to_find.inspect} child-of:#{sexp.inspect} current:#{path.inspect}"
      return @associated[to_find] if @associated.has_key? to_find
      sexp = @sexp if sexp.nil?
      path = []    if path.nil?
      return sexp  if to_find.empty?
      arr = is_a_sexp?(sexp) ? sexp.sexp_body : sexp
      arr.each_with_index {
         |inner_sexp, idx|
         # if the current element of to_find == the current idx
         if idx == to_find[path.length]
            if (path.length + 1) == to_find.length
                return inner_sexp
            else
                return find_path_sexp(to_find, inner_sexp, path + [idx])
            end
         end
      }
      raise "couldn't find index! find:#{to_find.inspect} childof:#{sexp.inspect} curr:#{path.inspect}"
   end
   def paths2orderdesc paths
      paths.collect { 
         |path|
         <<EOF
   #{path.inspect} (#{path2id path}),
      # => #{find_path_sexp(path).inspect}
EOF
      }.join ""
   end
end

# active profiling
class AstCursor
   attr_accessor :ast_id
   def initialize ast_id
      @ast_id = ast_id
   end
   def hits_for_id func, slow_id
      idx = ProfFuncWithMd::md_find_in_caller_map func, slow_id
      idx.nil? ? 0 : func.profile_hash[idx]
   end
   def id_hit? old_functions, get_count = false
      count = 0
      old_functions.each {
         |func|
         next if ProfFuncWithMd::md_get_path_range(func).nil? or func.profile_hash.nil?
         if ProfFuncWithMd::md_get_path_range(func).include? @ast_id
            count += hits_for_id func, @ast_id
            break if !get_count and count > 0
         end
      }
      get_count ? count : (count > 0)
   end
end

class LoggedHash < Hash
   def initialize name
      @name = name
   end
   def []= a, b
      puts cyan("Hash::#{@name} -- setting key #{a.inspect} with value #{b.inspect}")
      super a, b
   end
   def [] a
      tmp = super a
      puts cyan("Hash::#{@name} -- (key #{a} -> #{tmp})")
      return tmp
   end
end

module NN
   def self.mk_type func, type_sym
      fail "sorry #{type_sym.inspect} is an invalid type!" unless Typing::ID_MAP.has_key? type_sym
      return mk_constant(func, :int, Typing::ID_MAP[type_sym])
   end
   def self.mk_constant func, constant_type, integer
      return_value = Value.new
      func.fill_value_with_constant return_value, constant_type, integer
      return_value 
   end
   def self.mk_bytearray func, length
      size = Value.new
      func.fill_value_with_constant size, :int, length
      alloced_global_addr = Value.new
      func.insn_call_alloc_bytearray alloced_global_addr, size
      alloced_global_addr 
   end
end

module Typing
   ID_MAP = [
      :nil, :bool, :int, :type, :block, :const, :bytearray, :undef, :multi_arg
   ].inject({}) { |h,s| h.merge({s=>h.size+1}) }
end

module PostProcs
   CHAR = proc { |id| id.chr }
   ID   = proc { |id| id.id2name }
   NULL = proc { |id| id.to_s }
   TYPE = proc { |type_id| Typing::ID_MAP.index(type_id).to_s }
end

RuntimePrintCallback = Struct.new :postproc, :value # rename - RuntimePrinter

class DebugLogger
   $message_hash, $message_hash_post_proc = {}, {}

   def self.add_message id, string, &block
      $message_hash[id] = string
      if !block.nil?
         $message_hash_post_proc[id] = block
      end
   end

   def self.runtime_print_string func, *values, &block
      if values.first.is_a? Symbol
         stream = values.shift
         return unless check_dbg(stream)
      end
      # puts "GOING TO ADD SOMETHING ARGH! - #{values.inspect}"
      values.unshift "RT: " if $debug
      values.each {
         |value|
         if value.is_a? String
            DebugLogger::add_message value.object_id, value, &block
            func.insn_call_print_int NN::mk_constant(func, :int, value.object_id)
         elsif value.is_a? RuntimePrintCallback
            DebugLogger::add_message value.postproc.object_id, "", &value.postproc
            func.insn_call_print_int NN::mk_constant(func, :int, value.postproc.object_id)
            if !value.value.nil?
               func.insn_call_print_int value.value 
            else
               func.insn_call_print_int NN::mk_constant(func, :int, 0)
            end
         else
            DebugLogger::add_message value.object_id, "", &PostProcs::NULL
            func.insn_call_print_int NN::mk_constant(func, :int, value.object_id)
            func.insn_call_print_int value
         end
      }
   end
end

class MemContext
   attr_accessor :stack_mem, :return_stack_mem, :all_locals_mem,
      :locals_mem, :return_rbstack, :locals_dict
   def initialize stack_mem, return_stack_mem, all_locals_mem, locals_mem
      @stack_mem, @return_stack_mem, @all_locals_mem, @locals_mem = \
         stack_mem, return_stack_mem, all_locals_mem, locals_mem 
   end
   def flush
      @return_rbstack.flush if @return_rbstack
      @locals_dict.flush if @locals_dict
   end
   def can_flush?
      (!@return_rbstack.nil? || !@locals_dict.nil?)
   end
end

class Comparison
   def self.right?
      ARGV.include? "--right"
   end
   def self.left?
      ARGV.include? "--left"
   end
end

module Comparisons
   def right?
      Comparison.right?
   end
   def left?
      Comparison.left?
   end
end

   class RbStack
      def initialize func, mem, sym, clever = false
         @virtual_stack = []
         @func, @mem, @sym, @clever = func, mem, sym, clever
         @clever = false if (ARGV.include? "--slow")
      end
      def pop_stack
         tmp = @virtual_stack
         @virtual_stack = []
         tmp
      end
      def push_stack stack
         fail "push_stack called with an already used stack!?" unless @virtual_stack.empty?
         @virtual_stack = stack
      end
      def stack_sym_info
         case @sym
         when :ret
            name = "return_stack"
            postproc = PostProcs::TYPE
         else
            name = "unknown"
            postproc = PostProcs::NULL
         end
         return name, postproc
      end
      def push value, type
         puts "push_to_stack - #{caller[0..1].join " -- "}" if check_dbg(:rt_primitives)
      if @clever
#        puts "#{self}: PUSHING on to the stack"
         @virtual_stack.push [value, type]
#        puts "#{self}: virtual stack -> #{@virtual_stack.inspect}"
         return
      end
         push_raw value, type
      end
      def push_raw value, type
#        puts "push_raw!!!"
         orig_stack_position = Value.new
         @func.insn_load_elem orig_stack_position, @mem, NN::mk_constant(@func, :int, 0), :int
         temp = Value.new
         @func.insn_add temp, orig_stack_position, NN::mk_constant(@func, :int, 1)
         @func.insn_store_elem @mem, temp, value
         # type is high
         @func.insn_add temp, orig_stack_position, NN::mk_constant(@func, :int, 2)
         @func.insn_store_elem @mem, temp, type
         if check_dbg(:rt_stack)
            name, postproc = stack_sym_info
            DebugLogger::runtime_print_string @func, name, ".push( ", temp, " => ", value,
                  " : type ", RuntimePrintCallback.new(postproc, type), " )\n"
         end
         @func.insn_store_elem @mem, NN::mk_constant(@func, :int, 0), temp
         orig_stack_position
      end
      def pop
         puts "pop_from_stack - #{caller.first}" if check_dbg(:rt_primitives)
      if @clever
         if @virtual_stack.empty?
            # TODO - find out if its valid that this is frequently the clause followed true!
#           puts "#{self}: POPPING from below the stack!"
         else
#           puts "#{self}: A Normal Pop"
            value, type = *(@virtual_stack.pop)
#           puts "#{self}: virtual stack -> #{@virtual_stack.inspect}"
            return value, type
         end
      end
#        puts "pop_raw!!!"
         orig_stack_position, type, value = Value.new, Value.new, Value.new
         @func.insn_load_elem orig_stack_position, @mem, NN::mk_constant(@func, :int, 0), :int
         # FIXME - rename temp to new_position
         temp = Value.new
         # type is high
         @func.insn_load_elem type, @mem, orig_stack_position, :int
         @func.insn_sub temp, orig_stack_position, NN::mk_constant(@func, :int, 1)
         @func.insn_load_elem value, @mem, temp, :int
         @func.insn_sub temp, orig_stack_position, NN::mk_constant(@func, :int, 2)
         if check_dbg(:rt_stack)
            name, postproc = stack_sym_info
            zero = NN::mk_constant(@func, :int, 0)
            lt_result = Value.new
            skip_fail = Label.new
            DebugLogger::runtime_print_string @func, name, ".pop( ", temp, " => ", value,
               " : type ", RuntimePrintCallback.new(postproc, type), " )\n"
            @func.insn_lt lt_result, temp, zero
            @func.insn_branch_if_not lt_result, skip_fail
            @func.insn_fail
            @func.insn_label skip_fail
         end
         @func.insn_store_elem @mem, NN::mk_constant(@func, :int, 0), temp
         return value, type
      end
      def flush
      if @clever
#        puts "#{self}: PUSHING exit stack [#{@virtual_stack.inspect}] - #{caller.first}"
         @virtual_stack.each { |top| push_raw *top }
      end
      end
   end

class FieldDesc 
   attr_reader :position, :type
   def initialize position, type
      @position, @type = position, type
   end
   def load func, mem
      tmp = Value.new
      func.insn_load_elem tmp, mem, NN::mk_constant(func, :int, @position), @type
      tmp 
   end
   def store func, mem, value
      func.insn_store_elem mem, NN::mk_constant(func, :int, @position), value
   end
end

TypedLocal = Struct.new :value, :type

class DictLookup
   include Comparisons
   attr_accessor :func, :scope_linkage, :mem_ctx, :scope_ast_id, :needs_new_scope
   FIELD__CURRENT_SCOPE_ID = FieldDesc.new 1, :int # stack_mem
   def initialize eval_ctx, func, scope_linkage, mem_ctx
      idbg(:dbg_dictlookup) { magenta("----------- DICTIONARY CREATED -----------") }
      @eval_ctx, @func, @scope_linkage, @mem_ctx = eval_ctx, func, scope_linkage, mem_ctx
      @temps = {}
      @switched, @taken = false, false
      @needs_new_scope = false
   end
   def get_scope_from_id func, mem_ctx, current_scope_id 
      mem_tmp = Value.new
      idx_into_scopesstack = Value.new
      func.insn_add idx_into_scopesstack, current_scope_id, NN::mk_constant(func, :int, 1)
      func.insn_load_elem mem_tmp, mem_ctx.all_locals_mem, idx_into_scopesstack, :void_ptr
      DebugLogger::runtime_print_string func, :dict_lookup, "LOADED THE CURRENT SCOPE - ",
         current_scope_id, " (", mem_tmp , ")\n"
      mem_tmp 
   end
   def create_scope
      fail "erm. locals_mem was already set!" if !mem_ctx.locals_mem.nil?
      scope_mem, new_scope_id = @eval_ctx.create_new_scope @func, @mem_ctx, @scope_ast_id
      FIELD__CURRENT_SCOPE_ID.store @func, @mem_ctx.stack_mem, new_scope_id
      mem_ctx.locals_mem = scope_mem
      @needs_new_scope = false
      new_scope_id
   end
   def load_current_scope
      fail "erm. locals_mem was already set!" if !mem_ctx.locals_mem.nil?
      current_scope_id = FIELD__CURRENT_SCOPE_ID.load func, mem_ctx.stack_mem
      mem_tmp = get_scope_from_id(func, mem_ctx, current_scope_id)
      mem_ctx.locals_mem = mem_tmp
   end
   def flush
      return if @needs_new_scope
      idbg(:dbg_dictlookup) { magenta("----------- CREATING SCOPE -----------") }
      @temps.each_pair {
         |sym, local|
         raw_assign_value sym, local.value, local.type
      }
   end
   def assign_value local_sym, popped_int, type
      fail "sorry, you switched scope and then tried to use it directly after!" if @switched
      idbg(:dbg_dictlookup) { magenta("----------- #{local_sym} := <> -----------") }
      if not (@temps.has_key? local_sym)
         @temps[local_sym] = TypedLocal.new Value.new, Value.new
         @func.create_local @temps[local_sym].value, :int
         @func.create_local @temps[local_sym].type,  :int
      end
      @func.insn_store @temps[local_sym].value, popped_int
      @func.insn_store @temps[local_sym].type,  type
   end
   def raw_assign_value local_sym, popped_int, type, mem = nil
      mem ||= @mem_ctx.locals_mem
      create = proc {
         DebugLogger::runtime_print_string @func, :rt_assign, "new value created successfully!\n"
      }
      current_idx = DictHelpers::lookup_id_in_dict(@eval_ctx, @func, 
         local_sym.to_i, mem, @scope_linkage, &create)
      temp = Value.new
      @func.insn_store_elem mem, current_idx, popped_int
      @func.insn_add temp, current_idx, NN::mk_constant(@func, :int, 1)
      @func.insn_store_elem mem, temp, type
      if check_dbg(:rt_assign)
         type_sym = RuntimePrintCallback.new(PostProcs::TYPE, type)
         DebugLogger::runtime_print_string @func,
            "conditionally popping and locally assigning a value (",
            popped_int, ":", type_sym, ") to: #{local_sym} in mem ", mem, "\n"
      end
   end
   def load_local_var dict_id
      fail "sorry, you switched scope and then tried to use it directly after!" if @switched
      idbg(:dbg_dictlookup) { magenta("----------- #{dict_id} == ? -----------") }
      if @temps.has_key? dict_id
         return @temps[dict_id].value, @temps[dict_id].type
      else
         return raw_load_local_var(dict_id)
      end
   end
   def raw_load_local_var dict_id
      access = proc { 
         DebugLogger::runtime_print_string @func, "#{dict_id.to_s} not found in scope (",
            @mem_ctx.locals_mem, ") - NB. this can cause creation of the item as nil\n"
         @eval_ctx.gen_data_inspect @func, @mem_ctx
         @func.insn_return NN::mk_constant(@func, :int, 911)
      }
      current_idx = DictHelpers::lookup_id_in_dict(@eval_ctx, @func, dict_id.to_i,
                        @mem_ctx.locals_mem, @scope_linkage, &access)
      addr_plus_one, proc_addr, type = Value.new, Value.new, Value.new 
      @func.insn_load_elem proc_addr, @mem_ctx.locals_mem, current_idx, :int
      @func.insn_add addr_plus_one, current_idx, NN::mk_constant(@func, :int, 1)
      @func.insn_load_elem type, @mem_ctx.locals_mem, addr_plus_one, :int
      return proc_addr, type
   end
   def switch_to_scope_with_id func, scope_val, mem_ctx
      FIELD__CURRENT_SCOPE_ID.store func, mem_ctx.stack_mem, scope_val
      @switched = true
   end
   def force_creation
      create_scope if @needs_new_scope
   end
   def take_scope_id func, mem_ctx
      # at this point a delayed scope creation must actually be 
      # performed in order that we have a newly allocated scope id
      @taken = true
      return create_scope if @needs_new_scope
      return FIELD__CURRENT_SCOPE_ID.load(func, mem_ctx.stack_mem)
   end
end

Hints = Struct.new(:opt_call_cnt, :opt_call_dst, :opt_call_src)
class Hints
   def initialize hash
      hash.each_pair {
         |key, val|
         self.send("#{key}=".to_sym, val)
      }
   end
end

class DictHelpers

   def self.append_to_dict func, dict_mem, int_id, state_cache = nil
      ret, temp, count, temp_mult3, end_byte = Value.new, Value.new, nil, Value.new, Value.new
      DebugLogger::runtime_print_string func, :rt_find_index, "creating!\n"
   # dict_mem[0] := dict_mem[0] + 1
      if !state_cache.nil?
         if state_cache.count_local.nil?
            count = state_cache.count_local = Value.new
            func.create_local state_cache.count_local, :int
            func.insn_load_elem count, dict_mem, NN::mk_constant(func, :int, DICT_LENGTH_IDX), :int
         else
            count = state_cache.count_local
         end
      else
         count = Value.new
         func.insn_load_elem count, dict_mem, NN::mk_constant(func, :int, DICT_LENGTH_IDX), :int
      end
      func.insn_add temp, count, NN::mk_constant(func, :int, 1)
   # end_byte = (count * 3) + 1
      func.insn_mul temp_mult3, count, NN::mk_constant(func, :int, 3)
      func.insn_add end_byte, temp_mult3, NN::mk_constant(func, :int, 1)
   # dict_mem[end_byte] = id
      func.insn_store_elem dict_mem, end_byte, int_id
      func.insn_add ret, end_byte, NN::mk_constant(func, :int, 1)
      if state_cache.nil?
         func.insn_store_elem dict_mem, NN::mk_constant(func, :int, 0), temp
      end
      ret
   end

   def self.lookup_id_in_dict eval_ctx, func, int_id, dict_mem, scope_linkage
      actual_int_id = int_id
      if (!int_id.is_a? Value) && $opt_scope_templates
         scope_hash = eval_ctx.scope_hash
         idbg(:scope_templates) { "CHECKING IF WE CAN REUSE!!! #{int_id} -> #{int_id.id2name} - " +
                                 "#{ProfFuncWithMd::md_inspect func.metadata}\n#{scope_hash.inspect}" }
         if int_id.id2name.nil?
            puts "EEK, NO SYMBOL! #{caller[0..2]}"
         end
         scope_id = ProfFuncWithMd::md_get_path_range(func).first
         pair_chained_to = scope_linkage.detect { |(k,v)| v.include? scope_id }
         if pair_chained_to 
            scope_creation_id = pair_chained_to[0]
            scope_id = scope_creation_id 
         end
         if scope_hash && scope = scope_hash[scope_id] # FIXME
            if int_id.id2name && sym = int_id.id2name.to_sym
               idx = scope.index sym
               if !idx.nil?
                  current_byte = 2 + 3*(idx)
                  idbg(:scope_templates) { "using #{sym} -> #{current_byte} : for scope #{scope_id}" }
                  ProfFuncWithMd::md_add_to_static_scope func, scope, scope_id, sym
                  pos_val = NN::mk_constant(func, :int, current_byte)
                  return pos_val 
               end
         end
         end
      end
      puts "dbg_lookup_id_in_dict - #{caller.first}" if check_dbg(:rt_primitives)
      int_id = int_id.is_a?(Value) ? int_id : NN::mk_constant(func, :int, int_id)
      current_byte = Value.new
      bench("dbg_lookup_id_in_dict") {
         # predeclare label(s)
         found, continue_looping, empty = Label.new, Label.new, Label.new
         temp, end_byte, cond_result, current_id = Value.new, Value.new, Value.new, Value.new, Value.new
         # end byte := (dict_mem[0] * 3) + 1
            func.insn_load_elem end_byte, dict_mem, NN::mk_constant(func, :int, 0), :int
            DebugLogger::runtime_print_string func, :rt_find_index_fine, "len = ", end_byte, "\n"
         # if (len == 0) goto empty
         DebugLogger::runtime_print_string func, :rt_find_index_fine, "blub= ", end_byte, "\n"
            func.insn_eq cond_result, end_byte, NN::mk_constant(func, :int, 0)
            func.insn_branch_if cond_result, empty
            func.insn_sub temp, end_byte, NN::mk_constant(func, :int, 1)
            func.insn_store end_byte, temp
         DebugLogger::runtime_print_string func, :rt_find_index_fine, "subbibg= ", end_byte, "\n"
            func.insn_mul temp, end_byte, NN::mk_constant(func, :int, 3)
            func.insn_store end_byte, temp
            func.insn_add temp, end_byte, NN::mk_constant(func, :int, 1)
            func.insn_store end_byte, temp
            DebugLogger::runtime_print_string func, :rt_find_index_fine, "current_byte = end_byte = ",
               end_byte, "\n"
         # set end_byte to 1, we start the search there
            func.create_local current_byte, :int
            func.insn_store current_byte, temp
         # while !at_end
         # { loop again
            loop_again = Label.new
            func.insn_label loop_again
               # at_end := (current_byte == initial_byte)
                  func.insn_eq cond_result, current_byte, NN::mk_constant(func, :int, 1)
                  DebugLogger::runtime_print_string func, :rt_find_index_fine, "should finish? == ", 
                     cond_result, "\n"
               # comparable := (dict_mem[current_byte + 0] == int_id)
                  func.insn_load_elem current_id, dict_mem, current_byte, :int
                  id_comparison_result = Value.new
                  func.insn_eq id_comparison_result, current_id, int_id
               # if (comparable) {
                  func.insn_branch_if_not id_comparison_result, continue_looping
                     sym = RuntimePrintCallback.new(PostProcs::ID, int_id)
                     DebugLogger::runtime_print_string func, :rt_find_index_fine, 
                        "it ", sym, "(", int_id, ") matches! at position ", current_byte, "\n"
                     # current_byte := current_byte + 1
                        func.insn_add temp, current_byte, NN::mk_constant(func, :int, 1)
                        func.insn_store current_byte, temp
                     # break
                        func.insn_branch found
               # }
                  func.insn_label continue_looping
               # current_byte := current_byte + 3
                  func.insn_sub temp, current_byte, NN::mk_constant(func, :int, 3)
                      # decrement by 3 each time
                  func.insn_store current_byte, temp
               # NOTE - see above
                  DebugLogger::runtime_print_string func, :rt_find_index_fine,
                     "checking loop.. (", cond_result, ")\n"
         # }
         # if (!found) {
                  func.insn_branch_if_not cond_result, loop_again
                  func.insn_label empty
                  append_temp = DictHelpers::append_to_dict func, dict_mem, int_id
                  func.insn_store current_byte, append_temp
               # callback to generate more runtime
                  yield func if block_given?
            # }
         # done with looping or found section is finished
            func.insn_label found
      }
      if !actual_int_id.is_a? Value
         DebugLogger::runtime_print_string func, 
            :rt_find_index, "rt lookup for #{actual_int_id.id2name} result pos: ", current_byte, "\n"
         ProfFuncWithMd::md_add_to_lookup_for_debug func, actual_int_id.id2name
         DebugLogger::runtime_print_string func, 
            :rt_data_inspect_force, "forcing data inspect, due to lookup of #{actual_int_id.id2name}\n"
      end
      ProfFuncWithMd::md_force_data_inspect func
      current_byte
   end
end

class StateCache
   CACHE_FILE = "/tmp/rubydium.pstore"

   def self.save_cache machine
      y = PStore.new CACHE_FILE
      y.transaction {
         y['cache_id']        = machine.cache_id
         y['scope_hash']      = machine.scope_hash
         y['node2type_cache'] = machine.node2type_cache
         y['scope_linkage']   = machine.scope_linkage
         if dbg_on :cache_store
            puts "AT SAVE!"
            pp y
         end
      }
   end

   def self.load_cache machine
      begin
         y = PStore.new CACHE_FILE
         y.transaction {
            return false if machine.cache_id != y['cache_id'] or (ARGV.include? "--ignore-cache")
            machine.scope_hash      = y['scope_hash']
            machine.node2type_cache = y['node2type_cache']
            machine.scope_linkage   = y['scope_linkage']
            if dbg_on :cache_store
               puts "AT LOAD!"
               pp y
            end
         }
      rescue => e
         puts "FAILURE LOADING CACHE - REMOVING"
         File.delete(CACHE_FILE)
         return false
      end
   end
end


DICT_LENGTH_IDX = 0
DictAppendCache = Struct.new :count_local
