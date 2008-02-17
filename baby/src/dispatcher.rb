require './clean.rb'

# line counts (this + clean.rb): 
# 28/12/07 - 3165
# 03/01/08 - 3302
# 04/01/08 - 3215
#   (wc src/dispatcher.rb clean.rb)

$enable_cache = true

class EvalMachine

   attr_accessor :object, :self_type, :old_functions, :scope_hash, :time_vs_instructions_log, :ast_order, :source
   attr_reader :crawler

   attr_accessor :cache_id, :scope_hash, :node2type_cache, :scope_linkage

   # prototype
   ATOM_RET_VAL = :int

   # param positions
   STACK_BYTEARRAY_PARAM_IDX        = 0
   RETURN_STACK_BYTEARRAY_PARAM_IDX = 1
   ALL_LOCALS_BYTEARRAY_PARAM_IDX   = 2

   # id's
   OUTER_SCOPE  = -16
   INITIAL_PREV = -8
   NULL_BLOCK   = -4
   FORCED_POP   = -2
   FINISHED     = -1
   ID_CONSTANTS = [:INITIAL_PREV, :NULL_BLOCK, :FORCED_POP, :FINISHED] # TODO - what about outer_scope ?

   """ init system """
   def initialize ctx, string
      @cache_id = Digest::MD5.digest string
      @scope_hash = {}
      @old_functions = []
      @func_cache = {}
      @func_cache_hits, @func_cache_misses = 0, 0
      @rp      = RubyParser.new
      @sexp    = @rp.parse string
      @source  = string
      @crawler = CodeTree.new @sexp
      @context = ctx
      @context.make_comment = proc {
         make_comment
      }
      @context.my_callback = proc {
         |value|
         my_callback value.to_s
      }
      @context.builder_function = proc {
         |curr_id, prev_id, got_num_params, wib|
         build_function curr_id, prev_id, got_num_params, wib, false
      }
      @context.data_inspector = proc {
         |ptr1, ptr2, ptr3, ptr4|
         my_data_inspect ptr1, ptr2, ptr3, ptr4
      }
      $str_buffer = ""
      @node2type_cache = $debug_logged_cache ? LoggedHash.new("node2type_cache") : {}
      @time_vs_instructions_log = []
      @execution_started_at = Time.now
      @scope_linkage = { OUTER_SCOPE => [] }      
      if $enable_cache && StateCache::load_cache(self)
         puts "loaded from cache!" 
      end
   end

   def make_comment
      method_trace = caller[1..-1].reject {
         |l|
         l =~ %r(test/unit|testing.rb) }.map { |l| l.gsub(/.*?:(\d+)(:in \`(.*)')?/, "\\3:\\1") }
      method_trace[1..-1].join ", "
   end
   
   """ describe a given path id, for interactive debugging """
   def desc id # DEBUG HELPER
      path = @crawler.id2path id
      @crawler.find_path_sexp(path).inspect + " :: context[ " + crawler.find_path_sexp(path[0..-2]).inspect + " ]"
   end
   
   def number_of_generated_instructions
      old_functions.inject(0) { |a,func| a + func.size }
   end

   def number_of_instructions_executed
      old_functions.inject(0) { |a,func| a + func.instructions_executed }
   end
   
   def smallest_path paths
      path_lengths = paths.map { |path| path.length }
      return (paths.enum_for(:each_with_index).detect { |path, idx| path.length == path_lengths.min })[0]
   end

   AnonBlock = Struct.new :yielder_subpaths, :subpaths, :dyn_assigns

   """ generate the execution paths, splitting blocks out into AnonBlock's"""
   def gen_orders
      # filter ast tree
      @ast_order = @crawler.id2path_hash.keys.sort.collect { 
         |id|
         path = @crawler.id2path_hash[id]
         sexp_subtree = @crawler.find_path_sexp(path)
         type = sexptype(sexp_subtree)
         next unless (!([nil, :array].include? type) || (sexp_subtree == :push_block)) \
                  && type != :block
         path
      }.compact
      idbg(:gen_orders) { "ALL : #{@crawler.paths2orderdesc @ast_order}" }
      # handle anon block definitions
      done_paths = []
      @path2anon_block = {}
      while true
         anon_block_path = @ast_order.detect { |path| sexp = @crawler.find_path_sexp(path); 
                                                (sexptype(sexp) == :iter) \
                                                and !done_paths.include? path }
         break if anon_block_path.nil?
         anon_block = AnonBlock.new
         yielder_rootpath = anon_block_path + [0]
         anon_block.yielder_subpaths = CodeTree.find_subpaths(@ast_order, yielder_rootpath) + [yielder_rootpath]
         anon_block.yielder_subpaths.each { |path| @ast_order.delete path }
         idbg(:gen_orders) { "YIELDER CALL : #{@crawler.paths2orderdesc anon_block.yielder_subpaths}" }
         anon_block.subpaths = CodeTree.find_subpaths(@ast_order, anon_block_path)
         anon_block.subpaths.each { |path| @ast_order.delete path }
         # remove the elements performing iterator param bindings
         anon_block.dyn_assigns = []
         loop {
            sexp_element = @crawler.find_path_sexp(anon_block.subpaths.first)
            break unless ([:dasgn_curr_hacked, :dasgn_curr, :lasgn].include? sexptype(sexp_element))
            has_value = (sexp_element.length < 2 or sexp_element[2].nil?)
            break unless has_value
            path = anon_block.subpaths.slice!(0)
            anon_block.dyn_assigns << path
         }
         idbg(:gen_orders) { "ANON BLOCK : #{@crawler.paths2orderdesc anon_block.subpaths}" }
         done_paths << anon_block_path
         (anon_block.yielder_subpaths + anon_block.subpaths + [anon_block_path]).each {
            |path|
            @path2anon_block[path] = anon_block 
         }
      end
      idbg(:gen_orders) { "MAIN : #{@crawler.paths2orderdesc @ast_order}" }
      idbg(:stackify) {
         @crawler.id2path_hash.keys.sort.collect { 
            |key| 
            "#{key} => #{@crawler.id2path_hash[key].inspect}" 
         }.join "\n"
      }
   end

   $builtins = [:alloc_self, :set_self, :dget, :dset, :set, :get, :typeof, :putch, :pi, :+, :-, :*, :/, :%, :==, :<, :>, :"!="]


   def is_function_call sexp
      [:call, :vcall, :fcall].include? sexptype(sexp)
   end
      
   """ is the node a call to a instrinsic function? """
   def is_builtin? sexp
      (is_function_call(sexp) and $builtins.include? get_method_name(sexp))
   end

   """ decide if we wish to follow this trace or cut it short at this point with various heuristics """
   def will_predict? curr_id, next_id, skip_data_inspect, func
      idbg(:node_predict) { green("will_predict?") + " #{curr_id.inspect}, #{next_id.inspect}" }
      curr_sexp = @crawler.find_path_sexp @crawler.id2path(curr_id)
      next_sexp = @crawler.find_path_sexp @crawler.id2path(next_id)
      idbg(:node_predict) { "current :: #{curr_sexp.inspect}, next :: #{next_sexp.inspect}" }
      return false if @calling_function or !$opt_use_predict
      parent_sexp = @crawler.find_path_sexp((@crawler.id2path curr_id).slice(0..-2))
      if (sexptype(parent_sexp) == :while) and parent_sexp[1] === curr_sexp
         return false
      end
      # special case int.call()'s
      if (sexptype(curr_sexp) == :const) and (sexptype(next_sexp) == :call)
         @literal_receiver = :Const
         idbg(:node_predict) { "next is a new call on a const, lets predict! - #{next_id.inspect}" }
         return true
      end
         if (sexptype(curr_sexp) == :call) and @literal_receiver == :Const
            @literal_receiver = nil
            idbg(:node_predict) { "preforming a new call on a const, lets predict! - #{next_id.inspect}" }
            return true
         end
      if is_builtin? next_sexp
         @called_builtin = true
         idbg(:node_predict) {
            "next is a #{sexptype(next_sexp)}::#{get_method_name next_sexp} call, lets predict! - #{next_id.inspect}"
         }
         return true
      end
         if !@called_builtin.nil? and is_builtin? curr_sexp
            @called_builtin = nil
            idbg(:node_predict) {
               "performed a #{sexptype(curr_sexp)}::#{get_method_name curr_sexp}!, lets predict! - #{next_id.inspect}"
            }
            return true
         end
      if is_function_call(next_sexp) and @node2type_cache.has_key? next_id
         idbg(:node_predict) {
            "predicting the next one - #{next_id} - #{next_sexp.inspect} - #{@node2type_cache[next_id].inspect}"
         }
         return true
      end
      # FIXME - removed an unused special path for call and integer from here!
      @literal_receiver = nil
      @called_builtin = nil
      return false unless skip_data_inspect
      if ProfFuncWithMd::md_is_not_real? func
         idbg(:node_predict) { "node isn't real!, lets predict! - #{next_id.inspect}" }
         return true
      end
      if [:while, :true, :false, :str, :lit, :lvar, :lasgn, :const, :dvar, :push_block].include? sexptype(curr_sexp)
         idbg(:node_predict) { "got #{curr_sexp.inspect}, lets predict! - #{next_id.inspect}" }
         return true
      end
      idbg(:node_predict) { "like, screw this you guys, i'm not predicting" }
      false
   end

   """ generate a data inspect call for the given memory context """
   def gen_data_inspect func, mem_ctx
      func.insn_call_data_inspect mem_ctx.stack_mem, mem_ctx.return_stack_mem, 
         NN::mk_constant(func, :int, 0), mem_ctx.all_locals_mem
   end

   def construct_prototype_of_length num_params
      # stack mem, return stack, all locals mem
      [:void_ptr] * (num_params + 3)
   end

   """ data structure used to abstract various information about a bounced jump in the flow """
   Dispatch = Struct.new :bouncer, :scope_val, :already_flushed, :params

   """ generate a dispatch based on a Dispatch descriptor """
   def do_dispatch func, mem_ctx, dispatch
      mem_ctx.locals_dict.switch_to_scope_with_id func, dispatch.scope_val, mem_ctx unless dispatch.scope_val.nil?
      mem_ctx.flush if mem_ctx.can_flush? and !dispatch.already_flushed
      return_value = Value.new
      params = dispatch.params || []
      pos = func.insn_call_indirect_vtable_blah \
               return_value, dispatch.bouncer,
               ATOM_RET_VAL, construct_prototype_of_length(params.length*2), 
               [mem_ctx.stack_mem, mem_ctx.return_stack_mem, mem_ctx.all_locals_mem, *(params.flatten)]
      func.insn_return return_value
      pos
   end

   """ generate a static jump to the given position in the flow """
   def generate_static_jump next_id, func, mem_ctx, is_bouncer
      return_value = Value.new
      currently_generating = (next_id == @func_ids.first)
      func_ptr = currently_generating ? func : @func_cache[next_id].func
      puts "CACHED FUNC_PTR - #{func_ptr.inspect}" if check_dbg(:rt_back_insertion)
      func_ptr_value = NN::mk_constant(func, :ptr, func_ptr)
      DebugLogger::runtime_print_string func, :rt_back_insertion, "jumping to back inserted function pointer! #{next_id}\n"
      if currently_generating
         DebugLogger::runtime_print_string func, :rt_back_insertion, "WOOOOOHOOO!! WE HIT A BRANCH OPT!\n"
         mem_ctx.flush if mem_ctx.can_flush?
         func.insn_branch ProfFuncWithMd::md_atom_main_label(func)
      else
         DebugLogger::runtime_print_string func, :rt_back_insertion, "performing a static dispatch\n"
         d = Dispatch.new func_ptr_value
         static_dispatch_pos = do_dispatch func, mem_ctx, d
      end
      ProfFuncWithMd::md_set_with_initial(func, :back_insertions, 0) { |c| c + 1 } unless is_bouncer
      ProfFuncWithMd::md_set_with_initial(func, :statically_dispatches_to, []) {
         |c| c << [next_id, static_dispatch_pos]
      } unless is_bouncer
#     fail "this really shouldn't be null!!!!" if static_dispatch_pos.nil?
   end
   
   """ generate a data inspect instruction if needed (has dynamic scope lookups or data inspect has been forced) """
   def handle_runtime_compiletime_data_transfer d, func, is_bouncer, skip_data_inspect, 
         next_point_val, mem_ctx, next_id, curr_id, num_params
      # FIXME - this next line has little to do with this method???
      idbg(:node_predict) { "writing a dispatch to #{next_id}" } if !next_id.nil?
      idbg(:dispatch_to_id_value) { "skip_data_inspect == #{skip_data_inspect}" }
      if $opt_scope_templates && !is_bouncer && (ProfFuncWithMd::md_not_all_static_lookups? func)
         DebugLogger::runtime_print_string func, :rt_data_inspect_force, "forcing a data inspect\n"
         ProfFuncWithMd::md_force_data_inspect func
      end
      flushed = false
      if !skip_data_inspect or $force_data_inspect or (ProfFuncWithMd::md_forced_data_inspect func)
         DebugLogger::runtime_print_string func, :rt_runtime_data_inspect_trace, "data inspect!!!!\n"
         # DebugLogger::runtime_print_string func, "data inspect!!!! - begun by #{caller.inspect}\n"
         mem_ctx.flush if mem_ctx.can_flush?
         flushed = true
         gen_data_inspect func, mem_ctx
         ProfFuncWithMd::md_set_with_initial(func, :call_data_inspect, 0) { |c| c + 1 }
      end
      d.already_flushed = flushed
   end

   """ generate a non static generation dispatch """
   def generate_dispatch func, is_bouncer, skip_data_inspect, next_point_val, mem_ctx, next_id, curr_id, num_params, perform_logging
      func_ptr = Value.new
      d = Dispatch.new func_ptr
      if perform_logging # FIXME - what is this for?
         handle_runtime_compiletime_data_transfer d, func, is_bouncer, skip_data_inspect,
            next_point_val, mem_ctx, next_id, curr_id, num_params
      else
         mem_ctx.flush if mem_ctx.can_flush?
         gen_data_inspect func, mem_ctx
      end
      fail "well, thats not good!" if next_point_val.nil?
      DebugLogger::runtime_print_string func, :rt_back_insertion, "performing a build function...\n"
      func.insn_call_build_function func_ptr, next_point_val, 
                                    NN::mk_constant(func, :int, curr_id), 
                                    NN::mk_constant(func, :int, num_params),
                                    NN::mk_constant(func, :ptr, func)
      DebugLogger::runtime_print_string func, :rt_back_insertion, "done build function\n"
      return_value = Value.new
      if perform_logging
         if !next_id.nil? # integer rather than dynamic
            ProfFuncWithMd::md_set_with_initial(func, :slow_dispatch_to, []) { |c| c << next_id }
         else
            ProfFuncWithMd::md_set_with_initial(func, :dynamic_dispatches, 0) { |c| c+1 }
         end
      end
      do_dispatch func, mem_ctx, d
   end

   """ jump to the given (possibly runtime) value based astid, performing an appropriate jump type """
   def dispatch_to_id_value func, mem_ctx, next_point_val, curr_id, num_params, 
         skip_data_inspect, no_predict = false, is_bouncer = false
      next_id = nil
      if next_point_val.is_a? Integer
         next_id = next_point_val
         next_point_val = NN::mk_constant(func, :int, next_point_val)
      end
      if !next_id.nil? && !no_predict && will_predict?(curr_id, next_id, skip_data_inspect, func)
         @predicting_next_id << next_id
         return
      end
      puts "LALA we gonna check if #{next_id} is like, already done yay! - #{@func_cache.keys.inspect}" \
         if check_dbg(:rt_back_insertion)
      link_statically = false
      if $opt_static_dispatches
         if !is_bouncer and ((@func_cache.has_key? next_id) \
            or (next_id == @func_ids.first and (ProfFuncWithMd::md_no_assumptions? func)))
            link_statically = true
         end
         if $new_optimized_returns and not (ProfFuncWithMd::md_optimal_return? func)
            idbg(:scope_templates) { "NO STATIC LINK AS ITS NON OPTIMAL WITH RESPECT TO RETURNS" }
            link_statically = false
         end
         if $opt_scope_templates and !is_bouncer and (ProfFuncWithMd::md_not_all_static_lookups? func)
            idbg(:scope_templates) {
               "NOT GONNA STATIC LINK TO #{next_id} AS ITS GOT A #{(ProfFuncWithMd::md_lookups func).inspect} LOOKUP!"
            }
            link_statically = false
         end
      end
      if link_statically
         skip_reoptimize = Label.new
         # we use the first of the reserved spots in the hit range
         func.insn_hit NN::mk_constant(func, :int, 0)
         cond = Value.new
         func.insn_hit_test cond, NN::mk_constant(func, :int, 0), NN::mk_constant(func, :int, 1000)
         func.insn_branch_if_not cond, skip_reoptimize
         DebugLogger::runtime_print_string func, :rt_call_param_opt, red("REOPTIMISATION PATH") + "!!!!:\n\n\n"
         generate_dispatch func, is_bouncer, skip_data_inspect, next_point_val, mem_ctx, next_id, curr_id, num_params, false
         func.insn_label skip_reoptimize
         DebugLogger::runtime_print_string func, :rt_call_param_opt, green("OPTIMAL") + "!!!\n\n\n"
         generate_static_jump next_id, func, mem_ctx, is_bouncer
      else
         generate_dispatch func, is_bouncer, skip_data_inspect, next_point_val, mem_ctx, next_id, curr_id, num_params, true
      end
   end

   """ does the given instruction that the ast path points to require a data inspect? """
   def should_skip_data_inspect? path
      if @node2type_cache.has_key? @crawler.path2id(path)
         idbg(:data_inspect) { "skipping a data inspect! ooo! - #{@crawler.find_path_sexp(path).class}" }
         return true
      end
      sexp = @crawler.find_path_sexp(path)
      !([:call, :fcall, :vcall, :iasgn, :ivar, :const].include? sexptype(sexp))
   end

   """ fill the data structure which represents variable scope with prefilled items if the id's are known, 
       possibly optimizing by memcpy'ing from a set of premade template scopes """
   def push_scope func, mem_ctx, scope, locals_mem, scope_ast_id
      if @scopescache_addr
         idbg(:create_new_scope) { "using a premade template!" }
         cached_idx, cache_len = cache_scope @scopescache_addr, scope
         cachescopes_ptr = get_cachescopes_pointer func, mem_ctx
         cache_addr = Value.new
         func.insn_load_elem cache_addr, cachescopes_ptr, NN::mk_constant(func, :int, cached_idx), :void_ptr
         func.insn_call_copy_bytearray locals_mem, cache_addr, NN::mk_constant(func, :int, cache_len)
         return
      end
      state_cache = DictAppendCache.new
      DebugLogger::runtime_print_string func, :rt_prefilling, 
         "scope prefilling for scope ", NN::mk_constant(func, :int, scope_ast_id), "\n"
      scope.each {
         |sym|
         val = RuntimePrintCallback.new(PostProcs::ID, NN::mk_constant(func, :int, sym.to_i))
         DebugLogger::runtime_print_string func, :rt_prefilling, "adding item  ", val, "\n"
         popped_int, type = NN::mk_constant(func, :int, 888), NN::mk_type(func, :undef)
         append_temp = DictHelpers::append_to_dict func, locals_mem, NN::mk_constant(func, :int, sym), state_cache
         # set the value
         func.insn_store_elem locals_mem, append_temp, popped_int
         # set the type
         temp = Value.new
         func.insn_add temp, append_temp, NN::mk_constant(func, :int, 1)
         func.insn_store_elem locals_mem, temp, type
      }
      if !scope.empty?
         # FIXME this is actually part of the append_to_dict logic
         func.insn_store_elem locals_mem, NN::mk_constant(func, :int, 0), state_cache.count_local
      end
      DebugLogger::runtime_print_string func, :rt_prefilling, "scope prefilling -> finished\n"
   end

   # we store the pointer in the type field
   """ create a new data structure representing variable scope """
   def create_new_scope func, mem_ctx, scope_ast_id
      idbg(:create_new_scope) { "creating new scope" }
      locals_mem = NN::mk_bytearray(func, 3 * 128 + 1) # struct: length, (id, type, value)*
      func.insn_store_elem locals_mem, NN::mk_constant(func, :int, 0), NN::mk_constant(func, :int, 0) # set length to 0
      # spare storage allocation: id (must be 0), spare, spare
      func.insn_store_elem locals_mem, NN::mk_constant(func, :int, 1), NN::mk_constant(func, :int, 0)
      all_locals = RbStack.new func, mem_ctx.all_locals_mem, :ret
      position_on_stack = all_locals.push_raw locals_mem, NN::mk_constant(func, :int, scope_ast_id)
      if $opt_scope_templates && @scope_hash && (scope = @scope_hash[scope_ast_id]) && !scope.empty?
         push_scope func, mem_ctx, scope, locals_mem, scope_ast_id
         ProfFuncWithMd::md_set_create_scope_template func, scope
      else
         DebugLogger::runtime_print_string func, :rt_data_inspect_force, "forcing a data inspect, cus of lack of prefilling\n"
         ProfFuncWithMd::md_force_data_inspect func
      end
      DebugLogger::runtime_print_string func, :create_new_scope, "NEW SCOPE AT POSITION : ", position_on_stack, "\n"
      return locals_mem, position_on_stack
   end

   FIELD__INDIRECTIONS_PTR = FieldDesc.new 4, :void_ptr # stack_mem

   def get_indirections_pointer func, mem_ctx
      return FIELD__INDIRECTIONS_PTR.load(func, mem_ctx.stack_mem)
   end

   FIELD__CACHESCOPES_PTR = FieldDesc.new 6, :void_ptr # stack_mem
   def get_cachescopes_pointer func, mem_ctx
      return FIELD__CACHESCOPES_PTR.load(func, mem_ctx.stack_mem)
   end

   def mk_bouncer curr_id, prev_id, num_params, func
      @bouncers ||= []
      ProfFuncWithMd::md_init_or_increase_bouncer_count func
      bouncer = Function.new @context
      ProfFuncWithMd::md_metadata bouncer
      ProfFuncWithMd::md_set_generated_by bouncer, func
      @old_functions << bouncer
      bouncer.lock {
         mem_ctx = MemContext.new Value.new, Value.new, Value.new, nil
         build_main_func_init bouncer, mem_ctx, curr_id
         mem_ctx.locals_dict = DictLookup.new(self, func, @scope_linkage, mem_ctx)
         puts "BUILDING A BOUNCER! - to #{curr_id} <- from #{prev_id}" if check_dbg(:rt_bouncer_runtime)
         if curr_id == NULL_BLOCK
            DebugLogger::runtime_print_string bouncer, "NULL BLOCK WAS CALLED!!\n"
            bouncer.insn_return NN::mk_constant(bouncer, :int, -666)
         elsif curr_id == FINISHED
            DebugLogger::runtime_print_string bouncer, :rt_bouncer_runtime, "AN EXIT BOUNCER!!\n"
            bouncer.insn_return NN::mk_constant(bouncer, :int, -666)
         elsif curr_id == FORCED_POP
            stack = RbStack.new bouncer, mem_ctx.stack_mem, :alt
            DebugLogger::runtime_print_string bouncer, :rt_bouncer_runtime, 
               "warning: popping bouncer!! - #{curr_id} <- #{prev_id} -> #{ProfFuncWithMd::md_inspect func.metadata}\n"
            pop_again = Label.new
            bouncer.insn_label pop_again
           # do
#           gen_data_inspect bouncer, mem_ctx
            bouncer_ptr, scope_val = stack.pop
            DebugLogger::runtime_print_string bouncer, :rt_bouncer_runtime, "popping! - ", bouncer_ptr, "\n"
            cond = Value.new
            bouncer.insn_eq cond, NN::mk_constant(bouncer, :int, FORCED_POP), bouncer_ptr
            bouncer.insn_branch_if cond, pop_again
           # repeat
            d = Dispatch.new bouncer_ptr
            d.scope_val = scope_val
            do_dispatch bouncer, mem_ctx, d
         else
            DebugLogger::runtime_print_string bouncer, :rt_bouncer_runtime, 
               "a bouncer going to #{curr_id} via dispatch_to_id_value - could be slow!\n"
            dispatch_to_id_value bouncer, mem_ctx, curr_id, prev_id, num_params, true, true, true
         end
         bouncer.compile
      }
      ProfFuncWithMd::md_set_next_id bouncer, curr_id
      ProfFuncWithMd::md_set_is_bouncer bouncer
      @bouncers << bouncer # garbage collection fix
      bouncer
   end

   # can setup and completion be made into two classes by making this an Initer and selecting the appropriate one?

   def jump_to_proc func, proc_addr, style_string
      stored_id = Value.new
      func.insn_load_elem stored_id, proc_addr, NN::mk_constant(func, :int, 0), :int
      stored_scope_id = Value.new
      func.insn_load_elem stored_scope_id, proc_addr, NN::mk_constant(func, :int, 1), :int
      if check_dbg(:rt_scope)
         DebugLogger::runtime_print_string func, "#{style_string} TO :", stored_id, ", with scope id :", stored_scope_id, "\n"
      end
      return stored_id, stored_scope_id
   end

   CachedCallData  = Struct.new(:type, :should_push_self)

   def pack_block func, statement_val, scope_val
      block_addr = NN::mk_bytearray(func, 2)
      func.insn_store_elem block_addr, NN::mk_constant(func, :int, 0), statement_val
      func.insn_store_elem block_addr, NN::mk_constant(func, :int, 1), scope_val
      block_addr
   end

   def create_null_packed_block func
      statement_val, scope_val = NN::mk_constant(func, :int, -555), NN::mk_constant(func, :int, -555)
      return pack_block(func, statement_val, scope_val)
   end

   def new_indirection_block func, mem_ctx, bouncer
      indirections = get_indirections_pointer func, mem_ctx
      position_on_stack = Value.new 
      func.insn_load_elem position_on_stack, indirections, NN::mk_constant(func, :int, 0), :int
      indirections_stack = RbStack.new func, indirections, :ret
      # TODO - use this free 777 for storing a compile time ref id!
      indirections_stack.push NN::mk_constant(func, :ptr, bouncer), NN::mk_constant(func, :int, 777)
      position_on_stack
   end

   def load_indirect_block func, block_indirection_idx, mem_ctx
      idx_into_indirections = Value.new
      func.insn_add idx_into_indirections, block_indirection_idx, NN::mk_constant(func, :int, 1)
      indirections = get_indirections_pointer func, mem_ctx
      dispatcher = Value.new
      func.insn_load_elem dispatcher, indirections, idx_into_indirections, :void_ptr
      dispatcher
   end
   
   def find_matching_method_path selected_func_defs, method
      selected_func_defs.keys.detect { |cpath| @crawler.find_path_sexp(cpath)[1] == method }
   end

   def do_method_dispatch func, mem_ctx, curr_id, has_receiver, method
      call_function, selected_func_defs = nil, nil
      if @node2type_cache.has_key? curr_id
         hit = @node2type_cache[curr_id]
         if hit.type == :Super
            selected_func_defs = @func_defs
         else
            selected_func_defs = @class_func_defs[hit.type]
         end
         if hit.should_push_self
            idbg(:dbg_handle_call_element) { "HIT - PUSHING SELF FROM __SELF__ WITH TYPE FROM cache! (#{hit.type})" }
            self_mem_ptr_ptr, dummy = mem_ctx.locals_dict.load_local_var :__self__
            mem_ctx.return_rbstack.push self_mem_ptr_ptr, NN::mk_type(func, hit.type.to_sym)
         end
         method_path = find_matching_method_path(selected_func_defs, method)
         call_function = selected_func_defs[method_path]
         # remove the type from the cache after the node has been specialized 
         # and indicate the atom as specialized (see ANN1 for more information)
         # @node2type_cache.delete curr_id TODO FIXME
         ProfFuncWithMd::md_set_specifalized func, [:on_type, hit.type]
      else
         idbg(:self_cache) { "RECEIVER CACHE MISS!!! - #{method}" }
         if !@object.nil? and has_receiver 
            @node2type_cache[curr_id] = CachedCallData.new(@object[0], false)
            selected_func_defs = @class_func_defs[@object[0]]
         elsif @self_type.nil?
            if @object.nil?
               @node2type_cache[curr_id] = CachedCallData.new(:Super, false)
               selected_func_defs = nil
            else
               if @object[0] == :const
                  @node2type_cache[curr_id] = CachedCallData.new(Typing::ID_MAP.index(@object[1]), false)
                  selected_func_defs = @class_func_defs[Typing::ID_MAP.index(@object[1])]
               else
                  @node2type_cache[curr_id] = CachedCallData.new(@object[0], false)
                  selected_func_defs = @class_func_defs[@object[0]]
               end
            end
         else 
            @node2type_cache[curr_id] = CachedCallData.new(@self_type, false)
            selected_func_defs = @class_func_defs[@self_type]
         end
         idbg(:dbg_handle_call_element) { "has_receiver == #{has_receiver}" }
         is_kernel = (selected_func_defs.nil?)
         selected_func_defs = @func_defs if selected_func_defs.nil?
         path = find_matching_method_path(selected_func_defs, method)
         if path.nil?
            is_kernel = true
            selected_func_defs = @func_defs
            path = find_matching_method_path(selected_func_defs, method)
         end
         if is_kernel
            @node2type_cache[curr_id].type = :Super
         end
         if !@self_type.nil? and !has_receiver and !is_kernel 
            @node2type_cache[curr_id].should_push_self = true
            idbg(:dbg_handle_call_element) { "PUSHING SELF FROM __SELF__ WITH TYPE FROM @self_type" }
            self_mem_ptr_ptr, dummy = mem_ctx.locals_dict.load_local_var :__self__
            mem_ctx.return_rbstack.push self_mem_ptr_ptr, NN::mk_type(func, @self_type.to_sym)
            ProfFuncWithMd::md_add_assumption func, [:assumption, :__self__, [:type, @self_type.to_sym]]
         elsif !@object.nil? and !has_receiver and !is_kernel 
            # if has_receiver
            @node2type_cache[curr_id].should_push_self = true
            idbg(:dbg_handle_call_element) { "PUSHING SELF FROM __SELF__ WITH TYPE FROM @object[0]" }
            self_mem_ptr_ptr, dummy = mem_ctx.locals_dict.load_local_var :__self__
            mem_ctx.return_rbstack.push self_mem_ptr_ptr, NN::mk_type(func, @object[0].to_sym)
            ProfFuncWithMd::md_add_assumption func, [:assumption, :object, [:type, @object, :todo]]
            @object = nil
         else
            ProfFuncWithMd::md_add_assumption func, [:assumption, :object, [:type, @object, :unknown_case]]
         end
         idbg(:dbg_handle_call_element) { killi <<-DBG
            OBJECT == #{@object.inspect}
            SELF   == #{@self_type.inspect}
            CALLING A METHOD ON A OBJECT OF ABOVE TYPE
         DBG
         }
         if !path.nil?
            call_function = selected_func_defs[path]
         else
            raise "no such method symbol: '#{method.inspect}'"
         end
      end
      call_function
   end

   def get_method_name sexp_element
      case sexptype(sexp_element)
      when :fcall
         method_name = sexp_element[1]
      when :call
         method_name = sexp_element[2]
      when :vcall
         method_name = sexp_element[1]
      else
         raise "foo - #{sexp_element}"
      end
      method_name
   end

   def handle_call_element sexp_element, func, mem_ctx, anon_block, curr_id, next_ast_path
      call_function = nil
      has_receiver = false
      # handle prototype specifics
      case sexptype(sexp_element)
      when :fcall
         num_params = (!sexp_element[2].nil?) ? (sexp_element[2][1..-1].length) : 0
      when :call
         num_params = (!sexp_element[3].nil?) ? (sexp_element[3][1..-1].length) : 0
         has_receiver = true
      when :vcall
         num_params = 0 # is this always correct???
      else
         raise "foo - #{sexp_element}"
      end
      method = get_method_name(sexp_element)
      case method
      when :typeof
         mem_ctx.return_rbstack.pop
         dummy, type = mem_ctx.return_rbstack.pop
         mem_ctx.return_rbstack.push type, NN::mk_type(func, :type)
      when :putch
         idbg(:dbg_handle_call_element) { "popping a char, printing it!!!!" }
         mem_ctx.return_rbstack.pop
         popped_int, type = mem_ctx.return_rbstack.pop
         if $debug
            DebugLogger::runtime_print_string func, "PrintChar: ", popped_int, " -> '", 
               RuntimePrintCallback.new(PostProcs::CHAR, popped_int), "'\n"
         else
            DebugLogger::runtime_print_string func, RuntimePrintCallback.new(PostProcs::CHAR, popped_int)
         end
         mem_ctx.return_rbstack.push NN::mk_constant(func, :int, -1), NN::mk_type(func, :nil)
      when :pi
         idbg(:dbg_handle_call_element) { "popping a value, printing it!!!!" }
         mem_ctx.return_rbstack.pop
         popped_int, type = mem_ctx.return_rbstack.pop
         if $debug
            DebugLogger::runtime_print_string func, "PrintInt: '", popped_int, "'\n"
         else
            DebugLogger::runtime_print_string func, popped_int, "\n"
         end
         mem_ctx.return_rbstack.push NN::mk_constant(func, :int, -1), NN::mk_type(func, :nil)
      when :breakpoint
         DebugLogger::runtime_print_string func, "BREAKPOINT CALLBACK\n"
      when :+, :-, :*, :/, :%
         # TODO - move into stdlib
         idbg(:dbg_handle_call_element) { "like erm, popping and doing a #{method}" }
         popped_int_1, type1 = mem_ctx.return_rbstack.pop
         mem_ctx.return_rbstack.pop # block
         popped_int_2, type2 = mem_ctx.return_rbstack.pop
         new_value = Value.new
         cmps_sym2method = { :+ => :insn_add, :- => :insn_sub, :* => :insn_mul, :/ => :insn_div, :% => :insn_rem }
         func.send cmps_sym2method[method], new_value, popped_int_1, popped_int_2
         mem_ctx.return_rbstack.push new_value, type1 # fixme
      when :==, :<, :>, :"!="
         # TODO - move into stdlib
         idbg(:dbg_handle_call_element) { "like erm, popping and doing a #{method}" }
         popped_int_1, type1 = mem_ctx.return_rbstack.pop
         mem_ctx.return_rbstack.pop # block
         popped_int_2, type2 = mem_ctx.return_rbstack.pop
         math_sym2method = { :== => :insn_eq, :"!=" => :insn_ne, :< => :insn_lt, :> => :insn_gt }
         new_value = Value.new
         func.send math_sym2method[method], new_value, popped_int_1, popped_int_2
         mem_ctx.return_rbstack.push new_value, NN::mk_type(func, :bool)
      when :call
         # acts on :block
         proc_addr, dummy = mem_ctx.return_rbstack.pop
         mem_ctx.return_rbstack.pop
         mem_ctx.return_rbstack.push create_null_packed_block(func), NN::mk_type(func, :block)
         block_indirection_idx, block_scope_id = jump_to_proc func, proc_addr, "CALLING"
         dispatcher = load_indirect_block func, block_indirection_idx, mem_ctx
         push_return_point_bouncer func, mem_ctx, curr_id, next_ast_path
         call_bouncer func, mem_ctx, dispatcher, block_scope_id
      when :alloc_self
         idbg(:dbg_handle_call_element) { "allocating some memory for self" }
         self_mem_ptr_ptr, dummy = mem_ctx.locals_dict.load_local_var :__self__
         mem_ctx.return_rbstack.pop
         self_mem = NN::mk_bytearray(func, 4096) # a large playground
         func.insn_store_elem self_mem_ptr_ptr, NN::mk_constant(func, :int, 0), self_mem
         # for dict's we clear the size and the first id
         func.insn_store_elem self_mem, NN::mk_constant(func, :int, 0), NN::mk_constant(func, :int, 0)
         func.insn_store_elem self_mem, NN::mk_constant(func, :int, 1), NN::mk_constant(func, :int, -5)
         func.insn_store_elem self_mem, NN::mk_constant(func, :int, 2), NN::mk_constant(func, :int, -5)
         mem_ctx.return_rbstack.push NN::mk_constant(func, :int, -1), NN::mk_type(func, :nil)
      when :set_self
         idbg(:dbg_handle_call_element) { "popping and setting self" }
         mem_ctx.return_rbstack.pop
         new_self_mem, dummy = mem_ctx.return_rbstack.pop
         self_mem_ptr_ptr, dummy = mem_ctx.locals_dict.load_local_var :__self__
         func.insn_store_elem self_mem_ptr_ptr, NN::mk_constant(func, :int, 0), new_self_mem
         mem_ctx.return_rbstack.push NN::mk_constant(func, :int, -1), NN::mk_type(func, :nil)
      when :set
# items such as this and the following several have a lot of duplication, 
# some of this can be solved in the cheap way by using an asm, however the
# real fix is to place the duplicate functionality in a helper
         idbg(:dbg_handle_call_element) { "setting the given int in self_mem" }
         self_mem_ptr_ptr, dummy = mem_ctx.locals_dict.load_local_var :__self__
         mem_ctx.return_rbstack.pop
         self_mem, idx_mult, idx_mult_add = Value.new, Value.new, Value.new
         value, type  = mem_ctx.return_rbstack.pop
         idx,   dummy = mem_ctx.return_rbstack.pop
         # calculate actual index
         func.insn_load_elem self_mem, self_mem_ptr_ptr, NN::mk_constant(func, :int, 0), :int
         func.insn_mul idx_mult, idx, NN::mk_constant(func, :int, 2)
         func.insn_store_elem self_mem, idx_mult, value
         func.insn_add idx_mult_add, idx_mult, NN::mk_constant(func, :int, 1)
         func.insn_store_elem self_mem, idx_mult_add, type
         mem_ctx.return_rbstack.push NN::mk_constant(func, :int, -1), NN::mk_type(func, :nil)
      when :dset
         idbg(:dbg_handle_call_element) { "setting the given int in self_mem (dict)" }
         self_mem_ptr_ptr, dummy = mem_ctx.locals_dict.load_local_var :__self__
         mem_ctx.return_rbstack.pop
         self_mem, idx_plus_one = Value.new, Value.new
         value, type = mem_ctx.return_rbstack.pop
         id,   dummy = mem_ctx.return_rbstack.pop
         # calculate actual index
         self_mem = Value.new
         func.insn_load_elem self_mem, self_mem_ptr_ptr, NN::mk_constant(func, :int, 0), :int
         current_idx = DictHelpers::lookup_id_in_dict(self, func, id, self_mem, @scope_linkage)
         func.insn_store_elem self_mem, current_idx, value
         func.insn_add idx_plus_one, current_idx, NN::mk_constant(func, :int, 1)
         func.insn_store_elem self_mem, idx_plus_one, type
         mem_ctx.return_rbstack.push NN::mk_constant(func, :int, -1), NN::mk_type(func, :nil)
      when :get
         idbg(:dbg_handle_call_element) { "pushing the first int in self_mem" }
         self_mem_ptr_ptr, dummy = mem_ctx.locals_dict.load_local_var :__self__
         mem_ctx.return_rbstack.pop
         self_mem, idx_mult, idx_mult_add = Value.new, Value.new, Value.new
         idx,  dummy = mem_ctx.return_rbstack.pop
         value, type = Value.new, Value.new
         # calculate actual index
         func.insn_load_elem self_mem, self_mem_ptr_ptr, NN::mk_constant(func, :int, 0), :int
         func.insn_mul idx_mult, idx, NN::mk_constant(func, :int, 2)
         func.insn_load_elem value, self_mem, idx_mult, :int
         func.insn_add idx_mult_add, idx_mult, NN::mk_constant(func, :int, 1)
         func.insn_load_elem type, self_mem, idx_mult_add, :int
         mem_ctx.return_rbstack.push value, type
         #
         type_sym = RuntimePrintCallback.new(PostProcs::TYPE, type)
         DebugLogger::runtime_print_string func, :rt_get, "self == ", self_mem, " value is (", value, ":", type_sym, ")"
      when :dget
         idbg(:dbg_handle_call_element) { "setting the given int in self_mem (dict)" }
         self_mem_ptr_ptr, dummy = mem_ctx.locals_dict.load_local_var :__self__
         mem_ctx.return_rbstack.pop
         self_mem, idx_plus_one = Value.new, Value.new
         id,   dummy = mem_ctx.return_rbstack.pop
         value, type = Value.new, Value.new
         # calculate actual index
         self_mem = Value.new
         func.insn_load_elem self_mem, self_mem_ptr_ptr, NN::mk_constant(func, :int, 0), :int
         current_idx = DictHelpers::lookup_id_in_dict(self, func, id, self_mem, @scope_linkage)
         func.insn_load_elem value, self_mem, current_idx, :int
         func.insn_add idx_plus_one, current_idx, NN::mk_constant(func, :int, 1)
         func.insn_load_elem type,  self_mem, idx_plus_one, :int
         mem_ctx.return_rbstack.push value, type
      when :proc
         # block, with its scope id, is pushed here due to handling of blocks in the 'when Call, FunCall, VCall'
         mem_ctx.return_rbstack.pop
         mem_ctx.return_rbstack.push NN::mk_constant(func, :int, -1), NN::mk_type(func, :nil)
      when :new
         idbg(:dbg_handle_call_element) { "USING OBJECT - #{@object}" }
         type_id = nil
         if !@literal_receiver.nil?
            type_id = @literal_receiver_attrib
         else
            raise ":new - non const" if @object[0] != :const
            type_id = @object[1]
            ProfFuncWithMd::md_add_assumption func, [:assumption, :object, [:type, type_id]]
         end
         idbg(:dbg_handle_call_element) { "pushing new object with type #{Typing::ID_MAP.index(type_id).inspect}" }
         mem_ctx.return_rbstack.pop # we don't need the block
         mem_ctx.return_rbstack.pop # or self
         self_mem = NN::mk_bytearray(func, 1)
         mem_ctx.return_rbstack.push self_mem, NN::mk_constant(func, :int, type_id)
      else
         call_function = do_method_dispatch func, mem_ctx, curr_id, has_receiver, method
         if (cached_type = @node2type_cache[curr_id]) && @build_hints && @build_hints.opt_call_src
         extra_params = cached_type.should_push_self ? 1 : 0
         extra_params += 1 # __block__
            if dbg_on :rt_call_param_opt
               puts "BUILDING OPTIMAL [PUSH] ROUTE #{curr_id} - #{caller.inspect}" if dbg_on :rt_call_param_opt
               DebugLogger::runtime_print_string func, "[OPTIMAL] #{curr_id} creating paramlist #{num_params+extra_params} vars\n"
            end
         else
            if dbg_on :rt_call_param_opt
               puts "BUILDING NON OPTIMAL ROUTE #{curr_id} - #{caller.inspect}"
               DebugLogger::runtime_print_string func, "[normal] #{curr_id} creating paramlist #{num_params}+? vars\n"
            end
         end
      end
      return call_function, num_params
   end

# bench badly needs to be replaced with a start / stop mechanic, the current version has too much code readability overhead

   def find_outer_element_of_type type, current_ast_path, inclusive = false
      # puts "find_outer_element_of_type -- #{caller[0..2].join " : "} -- #{type.inspect}"
      curr_path = current_ast_path.dup
      first = true
      type = [type] unless type.is_a? Array
      found = loop {
         sexp = @crawler.find_path_sexp curr_path
         break true if (type.include? sexptype(sexp)) and ((inclusive and first) or (!first))
         curr_path.slice! -1
         break false if curr_path.empty?
         first = false
      }
      (found ? curr_path : nil)
   end

   def calc_num_yield_params current_sexp_element
      return 0 if current_sexp_element[1].nil?
      case current_sexp_element[1].first
      when :dvar, :lvar, :lit
         num_params = 1
      when :fcall
         num_params = 1
      else
         raise "unhandled - #{current_sexp_element[1].first}"
      end
      num_params 
   end

   def handle_element func, mem_ctx, current_sexp_element, current_ast_path, anon_block, next_ast_path, ast_order, curr_id
      call_function, num_params = nil, 0
      case sexptype(current_sexp_element)
      when :scope
         idbg(:handle_element) { "ignoring scope ast element" }
         ProfFuncWithMd::md_mark_not_real func
      when :class
         idbg(:handle_element) { "ignoring klass ast element" }
         ProfFuncWithMd::md_mark_not_real func
      when :const
         const = current_sexp_element[1]
         type_id = Typing::ID_MAP[const]
         idbg(:handle_element) { "pushing unvalued variable with type #{const.inspect} (#{Typing::ID_MAP[const]})!!!!" }
         mem_ctx.return_rbstack.push NN::mk_constant(func, :int, type_id), NN::mk_type(func, :const)
         @literal_receiver_attrib = (@literal_receiver == :Const) ? nil : type_id
      when :str
         ptr = Value.string2ptr current_sexp_element[1]
         mem_ctx.return_rbstack.push NN::mk_constant(func, :int, ptr), NN::mk_type(func, :bytearray)
      when :lit
         int = current_sexp_element[1]
         idbg(:handle_element) { "pushing #{int.inspect}!!!!" }
         mem_ctx.return_rbstack.push NN::mk_constant(func, :int, int), NN::mk_type(func, :int)
      when :false
         idbg(:handle_element) { "pushing false!!!!" }
         mem_ctx.return_rbstack.push NN::mk_constant(func, :int, 0), NN::mk_type(func, :bool)
      when :true
         idbg(:handle_element) { "pushing true!!!!" }
         mem_ctx.return_rbstack.push NN::mk_constant(func, :int, 1), NN::mk_type(func, :bool)
      when :dvar, :lvar # Self
         # if current_ast_element.is_a? Self
         #   local_sym = :__self__
         # else
            local_sym = current_sexp_element[1]
         # end
         idbg(:handle_element) { "pushing a locally assigned value - #{local_sym}" }
         stored_int, type = mem_ctx.locals_dict.load_local_var local_sym
         mem_ctx.return_rbstack.push stored_int, type
=begin
      when Def, Defs
         idbg(:handle_element) { "got a method definition! - #{next_ast_path.inspect}" }
         ProfFuncWithMd::md_mark_not_real func
=end
      when :block_arg
         idbg(:handle_element) { "skipping block arg element..." }
         block_sym = current_sexp_element[1]
         stored_int, type = mem_ctx.locals_dict.load_local_var :__block__
         idbg(:handle_element) { "associating __block__ with #{block_sym}" }
         mem_ctx.return_rbstack.push stored_int, type
         # store back to local
         mem_ctx.locals_dict.assign_value block_sym, stored_int, type
         # we didn't pop from the stack, so i don't *think* we need to push, right?
      when :iasgn, :ivar
         # push symbol
         mem_ctx.return_rbstack.push NN::mk_constant(func, :int, current_sexp_element[1].to_i), NN::mk_type(func, :int)
         method, num_params, clear_scope = ((sexptype(current_sexp_element) == :iasgn) ? :callhook : :callhookload), 1, true
         num_params += 1 if method == :callhook
         selected_func_defs = @class_func_defs[@self_type]
         self_mem_ptr_ptr, dummy = mem_ctx.locals_dict.load_local_var :__self__
         mem_ctx.return_rbstack.push create_null_packed_block(func), NN::mk_type(func, :block)
         mem_ctx.return_rbstack.push self_mem_ptr_ptr, NN::mk_type(func, @self_type.to_sym)
         # stack now == __self__ (top), __block__ (top-1)
         path = selected_func_defs.keys.detect { |cpath| @crawler.find_path_sexp(cpath)[1] == method }
         call_function = selected_func_defs[path]
         DebugLogger::runtime_print_string func, :rt_block, "pushing null block\n"
         ProfFuncWithMd::md_add_assumption func, [:assumption, :self, [:type, @self_type]]
      when :if
         ;
      when :lasgn, :dasgn_curr_hacked
         # pop the value, store to local, push the value again - as in, return it
         local_sym = current_sexp_element[1]
         idbg(:handle_element) { "popping and locally assigning a value to #{local_sym}" }
         popped_int, type = mem_ctx.return_rbstack.pop
         mem_ctx.locals_dict.assign_value local_sym, popped_int, type
         mem_ctx.return_rbstack.push popped_int, type
      when :call, :fcall, :vcall
         bench("handle calls") {
            f, n = handle_call_element current_sexp_element, func, mem_ctx, anon_block, curr_id, next_ast_path
            call_function, num_params = f, n if !f.nil?
         }
      when :iter
         subpaths = anon_block.yielder_subpaths
         idbg(:handle_element) { "CALLING PRODUCER OF ITERATOR : #{@crawler.paths2orderdesc subpaths}" }
         call_function = subpaths
      when :while
         next_ast_path, num_params = CodeTree.find_subpaths(ast_order, current_ast_path).first, 0
         idbg(:handle_element) { "WHILE :: should jump back to #{next_ast_path.inspect}" }
         # push something, way easier than other options...
         mem_ctx.return_rbstack.push NN::mk_constant(func, :int, -555), NN::mk_constant(func, :int, -555)
      when :yield
         proc_addr, dummy = mem_ctx.locals_dict.load_local_var :__block__
         block_indirection_idx, block_scope_id = jump_to_proc func, proc_addr, "YIELDING"
         dispatcher = load_indirect_block func, block_indirection_idx, mem_ctx
         num_params = calc_num_yield_params current_sexp_element
         push_return_point_bouncer func, mem_ctx, curr_id, next_ast_path
         marg_addr = NN::mk_bytearray(func, 4 * (1 + num_params)) # is this right?
         func.insn_store_elem marg_addr, NN::mk_constant(func, :int, 0), NN::mk_constant(func, :int, 0) # set position
         if num_params > 0
            # by popping each, and pushing onto a new list we reverse the order here
            multi_args_stack = RbStack.new func, marg_addr, :ret
            popped_int, type = mem_ctx.return_rbstack.pop
            multi_args_stack.push popped_int, type
         end
         mem_ctx.return_rbstack.push marg_addr, NN::mk_type(func, :multi_arg)
         mem_ctx.return_rbstack.push create_null_packed_block(func), NN::mk_type(func, :block)
         call_bouncer func, mem_ctx, dispatcher, block_scope_id
      when :break
         curr_path = find_outer_element_of_type(:while, current_ast_path)
         idx = ast_order.index curr_path
         next_ast_path = ast_order[idx + 1] # jump to the node *after* the while
         idbg(:handle_element) { "BREAKING TO : #{next_ast_path.nil? ? "nil" : (@crawler.paths2orderdesc [next_ast_path])}" }
         # umm break should return a val right? this is also a mini hack, related to the While push
         mem_ctx.return_rbstack.push NN::mk_constant(func, :int, -555), NN::mk_constant(func, :int, -555)
      when :push_block
         bouncer, scope = nil, nil
         if anon_block = @path2anon_block[current_ast_path] and anon_block.yielder_subpaths.include? current_ast_path
            idbg(:blocks) { "!!  @ @@ BAH   --- IN AN ITERATION WITH A BLOCK" }
            DebugLogger::runtime_print_string func, :rt_block, "pushing __block__\n"
            iteration_anon_block = @path2anon_block[current_ast_path]
            anon_block_first_statement_id = @crawler.path2id iteration_anon_block.subpaths.first
            current_scope_id = mem_ctx.locals_dict.take_scope_id func, mem_ctx
            bouncer = generate_continuation_bouncer(anon_block_first_statement_id, curr_id, 1, func) # a single multi-arg
            scope   = current_scope_id
            ProfFuncWithMd::md_set_with_initial(func, :creates_bouncer_to, []) { |c| c << anon_block_first_statement_id }
            # here create the compile time ref id, it contain the curr_id and anon_block_first_statement_id
            # if the compile time ref looks up and a preexisting indirection block is found, reuse!!!
            position_on_stack = new_indirection_block func, mem_ctx, bouncer
            mem_ctx.return_rbstack.push pack_block(func, position_on_stack, scope), NN::mk_type(func, :block)
         else
            subpaths = CodeTree.find_subpaths(ast_order, current_ast_path)
            # block_arg = subpaths.detect { |path| @crawler.find_path_ast(path).is_a? BlockArg }
            # block_already_present = !block_arg.nil?
            # FIXME - block args are broken, fix! and update the above code!
            block_already_present = false
            if !block_already_present
               idbg(:blocks) { "!!  @ @@ BAH   --- PUSHING A NULL BLOCK" }
               DebugLogger::runtime_print_string func, :rt_block, "pushing null block\n"
               packed_null_block = Value.new
               func.insn_load_elem packed_null_block, mem_ctx.stack_mem, NN::mk_constant(func, :int, 5), :void_ptr
               mem_ctx.return_rbstack.push packed_null_block, NN::mk_type(func, :block)
            end
         end
      else
         raise "wowzers, found an unhandled ast node! - #{current_sexp_element}"
      end
      return call_function, num_params, next_ast_path
   end

   def find_export_vars ts
      export_vars_list, export_special_vars, is_anon_block = nil, nil, false
      matching_func_def = @func_defs.values.detect { |order| (ts.path == order.first) }
      is_function = !matching_func_def.nil?
      export_special_vars = [:__block__]
      if !ts.anon_block.nil? and (ts.path == ts.anon_block.subpaths.first)
         export_vars_list = ts.anon_block.dyn_assigns.collect { 
            |path| 
            @crawler.find_path_sexp(path)[1]
         }
         is_anon_block = true
      elsif is_function
         func_order = matching_func_def 
         chosen_function_path = @func_defs.index func_order
         export_vars_list = @crawler.find_path_sexp(chosen_function_path)[2].dup
         # following is from when we grokked block args...
         # has_block_arg = !func_order.detect { |path| (@crawler.find_path_sexp(path)).is_a? Ruby::BlockArg }.nil?
         idbg(:dbg_find_export_vars) { "EXPORTING VARS, HAS BLOCK ARG == #{has_block_arg}" }
      else 
         # this code is just dire...
         first_func_statements = @class_func_defs.values.inject([]) { |h,a| h + a.values }.map { |l| l.first }
         if first_func_statements.include? ts.path
            outer_klass_path = find_outer_element_of_type(:class, ts.path)
            if !outer_klass_path.nil?
               idbg(:dbg_find_export_vars) { "\n\nIN CLASS!!" }
               outer_func_path  = find_outer_element_of_type([:defn_hacked],  ts.path)
               if !outer_func_path.nil?
                  idbg(:dbg_find_export_vars) { "IN FUNC" }
                  if (@class_func_defs[get_class_name(outer_klass_path)][outer_func_path].first rescue nil) == ts.path
                     # we have an outer class, for the moment this is good enough, 
                     # but, the exception of a Def inside a Def inside a Klass must later on be made
                     idbg(:dbg_find_export_vars) { "EXPORTING VARS FOR AN INSTANCE METHOD" }
                     export_special_vars = [:__block__, :__self__].reverse # THIS IS RIGHT DAMNNIT DO NOT CHANGE THIS
                     export_vars_list = @crawler.find_path_sexp(outer_func_path)[2]
                  end
               end
            end
         end
      end
      return export_vars_list, export_special_vars, is_anon_block
   end

   def cached_outer_element_find cache, current_ast_path, ast_order, inclusive, *element_types
      klass_path = nil
      if cache.has_key? current_ast_path
         klass_path = cache[current_ast_path]
      else
         klass_path = find_outer_element_of_type element_types, current_ast_path, inclusive
         cache[klass_path] = klass_path
      end
      klass_path 
   end

   def dump_class_func_defs
      str = ""
      @class_func_defs.each_pair {
         |klass_sym, func_defs|
         str << "CLASS #{klass_sym}" \
      + func_defs.map {
            |dom, rng|
            "  FUNCTION #{@crawler.find_path_sexp(dom).inspect}\n" \
         + @crawler.paths2orderdesc(rng)
         }.join("\n")
      }
      str
   end

   SkipDefinition = Struct.new :should_not_execute, :new_curr_id, :jump_ast_path

   # ast
   def handle_klass_definition klass_path, ast_order, curr_id, func
      new_class_name = get_class_name(klass_path)
      Typing::ID_MAP[new_class_name] = Typing::ID_MAP.values.max + 1
      idbg(:dbg_handle_definitions) { "DEFINING #{new_class_name}" }
      # we want to jump to the first subpath of the jump_ast_path 
      # not the path directly, otherwise we jump half way into code!
      inner_body_path = klass_path + [2, 1]
      next_path = CodeTree.find_subpaths(ast_order, inner_body_path).first
      # see test::test_empty_class_def
      if next_path.nil?
         idx = ast_order.index klass_path
         curr_id = @crawler.path2id ast_order[idx + 1]
         next_path = @crawler.id2path curr_id
      end
      ProfFuncWithMd::md_mark_not_real func
      return SkipDefinition.new(false, curr_id, next_path)
   end

   # ast
   def skip_to_end_of_method_def ast_order, curr_path, func
      last_ast = CodeTree.find_subpaths(ast_order, curr_path).last
      idx = ast_order.index last_ast
      # we modify the curr_id in order to prevent the eating of the non-existant return result
      curr_id = @crawler.path2id ast_order[idx + 1] # the Def
      jump_ast_path = ast_order[idx + 2]            # +1 -> def, +2 -> one after def
      ProfFuncWithMd::md_mark_not_real func
      return SkipDefinition.new(false, curr_id, jump_ast_path)
   end
   
   def get_class_name(path)
      @crawler.find_path_sexp(path)[1][2]
   end

   # definitions
   def handle_method_definition curr_path, klass_path, ast_order, current_ast_path, func
      if klass_path.nil?
         func_subpaths = CodeTree.find_subpaths(@ast_order, curr_path)
         if func_subpaths.first == current_ast_path and !@func_defs.has_key?(curr_path)
            @func_defs[curr_path] = func_subpaths
            return skip_to_end_of_method_def(ast_order, curr_path, func)
         end
      else
         # store ref to function def
         func_first_path = curr_path
         klass_name = get_class_name(klass_path)
         unless (@class_func_defs.has_key?(klass_name) and @class_func_defs[klass_name].has_key? func_first_path)
            idbg(:dbg_handle_definitions) { "DEFINING IT!" }
            func_subpaths = CodeTree.find_subpaths(@ast_order, func_first_path)
            @class_func_defs[klass_name] ||= {}
            @class_func_defs[klass_name][func_first_path] = func_subpaths
            idbg(:dbg_handle_definitions) { dump_class_func_defs }
            return skip_to_end_of_method_def(ast_order, curr_path, func)
         end
      end
      return nil
   end

   # definitions
   def handle_definitions ts, next_ast_path, ast_order, curr_id, func
      @handled_definitions ||= {}
      return SkipDefinition.new(true, curr_id, next_ast_path) if @handled_definitions.has_key? curr_id
      @handled_definitions[curr_id] = nil
      @klass_cache ||= {}
      @def_cache   ||= {}
      klass_path = cached_outer_element_find @klass_cache, ts.path, ast_order, false, :class
      if !klass_path.nil? and ts.path == klass_path + [0] # Colon2
         return handle_klass_definition(klass_path, ast_order, curr_id, func)
      end
      curr_path = cached_outer_element_find @def_cache, ts.path, ast_order, true, :defn_hacked, :def
      # FIXME - do this : shortcut optimisation: if past first node in a function we don't need to check, we just assume its not a define
      if !curr_path.nil? 
         result = handle_method_definition curr_path, klass_path, ast_order, ts.path, func
         return result if !result.nil?
      end
      return SkipDefinition.new(true, curr_id, next_ast_path)
   end

   # flow
   def export_vars func, mem_ctx, export_vars_list, export_special_vars, got_num_params, curr_id, is_anon_block
      idbg(:dbg_export_vars) { <<DBG
      found the function entry point - exporting vars #{export_vars_list.inspect}
                                       and special vars #{export_special_vars.inspect}
DBG
      }
      got_num_params += export_special_vars.length # add the special variables
      # function entry point
      idbg(:dbg_export_vars) { "got #{got_num_params} params!" }

      temp_cond, temp_idx = Value.new, Value.new
      # got_num_params includes __block__
      finished_loading = Label.new
      # normal load
      non_special_count = got_num_params - export_special_vars.length
      reversed_list = export_special_vars + export_vars_list.slice(0...non_special_count).reverse
      reversed_list.each_with_index {
         |local_sym, idx|
         popped_int, type = mem_ctx.return_rbstack.pop
         cond, skip_multi_load = Value.new, Label.new
         func.insn_eq cond, type, NN::mk_type(func, :multi_arg)
      # DebugLogger::runtime_print_string func, green("we got param of type: "), type, green("\n")
         func.insn_branch_if_not cond, skip_multi_load
         # multi load (when type == :multi_arg) - multi arg array is reversed, thusly its correct param order already
         multi_arg_end_pos = Value.new
         func.insn_load_elem multi_arg_end_pos, popped_int, NN::mk_constant(func, :int, 0), :int
         # load_multi_arg, takes params: num args (value), args (ruby array)
         pos = Value.new
         func.create_local pos, :int
         func.insn_store pos, NN::mk_constant(func, :int, 0)
         left_over_args = export_vars_list - reversed_list[0...idx]
         left_over_args.each {
            |arg_sym|
            end_loop_cond, add_temp = Value.new, Value.new
            offs_val, offs_type = Value.new, Value.new
            temp_val, temp_type = Value.new, Value.new
            func.insn_eq end_loop_cond, pos, multi_arg_end_pos 
            func.insn_branch_if end_loop_cond, finished_loading 
            func.insn_add offs_val, pos,  NN::mk_constant(func, :int, 1)
            func.insn_load_elem temp_val,  popped_int, offs_val,  :int
            func.insn_add offs_type, pos, NN::mk_constant(func, :int, 2)
            func.insn_load_elem temp_type, popped_int, offs_type, :int
         # DebugLogger::runtime_print_string func, "umm.. val == ", temp_val, ", and offset == ", temp_type, "\n"
            func.insn_add add_temp, pos,  NN::mk_constant(func, :int, 2)
            func.insn_store pos, add_temp 
            mem_ctx.locals_dict.assign_value arg_sym, temp_val, temp_type
         }
         func.insn_branch finished_loading
         func.insn_label skip_multi_load
         mem_ctx.locals_dict.assign_value local_sym, popped_int, type
      }
      func.insn_label finished_loading 
   end

   def sexptype sexp
      return sexp if sexp == :push_block
      (sexp.is_a? Sexp) ? sexp[0] : nil
   end

   # TODO this logic must be rewritten!
   def eat_unneeded_return_value func, mem_ctx, prev_id, ts
      # eat the previous statements return value if not needed
      previous_sexp_path = @crawler.id2path prev_id
      previous_sexp_element = @crawler.find_path_sexp previous_sexp_path
      unless [:iter, :class, :defn_hacked].include? sexptype(previous_sexp_element)
         # used to have or [:def].include?(sexptype(ts.sexp_elt))
         outer_element_path = previous_sexp_path.slice 0...-1
         outer_element_sexp = @crawler.find_path_sexp outer_element_path
         if outer_element_path != ts.path
            idbg(:dbg_eat_unneeded_return_value) { "OUTER PREV ELEMENT :: #{outer_element_sexp.inspect}" }
            case sexptype(outer_element_sexp)
            when :if, :while
               ;
            when :block
               idbg(:dbg_eat_unneeded_return_value) { "EATING LAST STATEMENTS RETURN VALUE" }
               mem_ctx.return_rbstack.pop unless [:if, :while].include? sexptype(ts.sexp_elt)
            end
         end
      end
   end

# should be refactored out into the per AST node type classes hierarchy / aspect blah blah

   def post_element func, mem_ctx, prev_id, curr_id, current_sexp, current_ast_path, ast_order
      outer_ast_path = @crawler.id2path curr_id
      outer_element_path = outer_ast_path.slice 0...-1
      if outer_element_path != current_ast_path and !(sexptype(current_sexp) == :break)
         outer_sexp = @crawler.find_path_sexp outer_element_path
         idbg(:dbg_post_element) { "OUTER ELEMENT :: #{outer_sexp.inspect}" }
         case sexptype(outer_sexp)
         when :if, :while
            mem_ctx.locals_dict.force_creation
            skip_repeat_dispatch = Label.new
            popped_conditional, type = mem_ctx.return_rbstack.pop
            func.insn_branch_if popped_conditional, skip_repeat_dispatch
            idx = ast_order.index outer_element_path
            jump_ast_path = ast_order[idx + 1]
            if !jump_ast_path.nil?
               elt = @crawler.find_path_sexp(jump_ast_path)
               jump_ast_path = nil if (sexptype(elt) == :defn_hacked)
            end
            if jump_ast_path.nil?
               idbg(:dbg_post_element) { "POPPING RETURN STACK" }
               # is there any reason that we'd want to use FORCED_POP and delay this?
               gen_return func, mem_ctx
            else
               idbg(:dbg_post_element) { "GOING TO JUMP TO #{jump_ast_path.inspect}" \
                                    + " - #{@crawler.find_path_sexp(jump_ast_path).inspect}" }
               next_curr_id = @crawler.path2id jump_ast_path 
               dispatch_to_id_value func, mem_ctx, next_curr_id, curr_id, 0, should_skip_data_inspect?(jump_ast_path), true
            end
            func.insn_label skip_repeat_dispatch
         end
      end
   end

   def elt_to_s elt
      ([:scope, :class, :defn_hacked].include? sexptype(elt)) ? sexptype(elt).to_s : elt.inspect
   end

   def generate_continuation_bouncer next_id, curr_id, num_params, func
      if next_id == FORCED_POP
         puts "no bouncer push" if check_dbg(:rt_bouncer)
         bouncer = mk_bouncer(FORCED_POP, curr_id, num_params, func)
      elsif @func_cache.has_key?(next_id) and $opt_static_conts
         puts "calling function! caching the return continuation!" if check_dbg(:rt_bouncer)
         ProfFuncWithMd::md_add_to_static_continuation_points func, next_id
         bouncer = @func_cache[next_id].func
      else
         puts "calling function with #{num_params} params! using a bouncer :(" if check_dbg(:rt_bouncer)
         ProfFuncWithMd::md_add_to_bouncing_cont_points func, next_id
         bouncer = mk_bouncer(next_id, curr_id, num_params, func)
      end
      bouncer
   end

   # create and push bouncer for jumping to position following the return of the yield  - FIXME - this should use the cache!
   def push_return_point_bouncer func, mem_ctx, curr_id, next_ast_path, num_params = -1
      next_id = (@crawler.path2id next_ast_path) || FORCED_POP
      bouncer = (generate_continuation_bouncer next_id, curr_id, num_params, func)
      current_scope_id = mem_ctx.locals_dict.take_scope_id func, mem_ctx
      stack = RbStack.new func, mem_ctx.stack_mem, :alt
      stack.push NN::mk_constant(func, :ptr, bouncer), current_scope_id
      DebugLogger::runtime_print_string func, :rt_bouncer_runtime, "pushing a return point bouncer and stuff yay\n"
   end

   def build_function_inner_inner mem_ctx, curr_id, prev_id, got_num_params, func, just_did_export, ts
      next_ast_path, num_params, ast_order = nil, nil, nil
      ProfilingFunction.record_hit(func, [:id, curr_id])
      DebugLogger::runtime_print_string func, :rt_runtime_curr_id_trace, "executing at id:#{curr_id} - #{elt_to_s ts.sexp_elt}\n"
      idbg(:dbg_build_function_inner_inner) {
         red("***BLOCK***") + " :: #{ts.sexp_elt.inspect}, PATH :: #{ts.path.inspect} (#{curr_id})"
      }
      if !just_did_export and (not [FORCED_POP, INITIAL_PREV, OUTER_SCOPE].include? prev_id)
         eat_unneeded_return_value func, mem_ctx, prev_id, ts
      end
      possible_orders = [@ast_order] + @func_defs.values
      possible_orders += [ts.anon_block.yielder_subpaths, ts.anon_block.subpaths] unless ts.anon_block.nil?
      ast_order = possible_orders.compact.detect { |path_list| path_list.include? ts.path }
      jump_type = handle_definitions ts, (ast_order[ast_order.index(ts.path) + 1]), ast_order, curr_id, func
      curr_id, next_ast_path = jump_type.new_curr_id, jump_type.jump_ast_path
      @calling_function = false
      if !jump_type.should_not_execute
         num_params = 0
      else
         if !next_ast_path.nil?
            # early exit from function def
            next_sexp = @crawler.find_path_sexp(next_ast_path)
            if (sexptype(next_sexp) == :defn_hacked) and ast_order.index(ast_order.index(next_ast_path) + 1).nil?
               next_ast_path = nil
            end
         end
         # handle element types
         call_function, num_params, next_ast_path = \
            handle_element func, mem_ctx, ts.sexp_elt, ts.path, ts.anon_block, next_ast_path, ast_order, curr_id
         post_element func, mem_ctx, prev_id, curr_id, ts.sexp_elt, ts.path, ast_order \
            unless prev_id == INITIAL_PREV or prev_id == FORCED_POP
         if !call_function.nil?
            # push next ast position, and old scope id
            idbg(:dbg_build_function_inner_inner) {
               "CALLING A FUNCTION! - WITH PARAMS #{num_params}, " \
             + "GOING TO #{next_ast_path.inspect} (#{@crawler.path2id(next_ast_path).inspect})"
            }
            push_return_point_bouncer func, mem_ctx, curr_id, next_ast_path, num_params
            next_ast_path = call_function.is_a?(Array) ? call_function.first : call_function
            idbg(:dbg_build_function_inner_inner) {
               "NEXT AST PATH :: #{@crawler.find_path_sexp(next_ast_path).inspect}"
            } if next_ast_path.is_a? Array
            # N.B next_ast_path != next_id
            @calling_function = true
         end
      end
      return curr_id, next_ast_path, num_params, ast_order
   end

   def gen_return func, mem_ctx
      idbg(:gen_return) { "popping next point from stack!" }
      # next on stack is the point to which we buncershould return, and the scope to which we return
      stack = RbStack.new func, mem_ctx.stack_mem, :alt
      bouncer, scope_val = stack.pop
      DebugLogger::runtime_print_string func, :rt_bouncer_runtime,
         "we're like, popping! -> to scope:", scope_val, " with bouncer ", bouncer, "\n"
      call_bouncer func, mem_ctx, bouncer, scope_val
   end

   def call_bouncer func, mem_ctx, bouncer, scope_val
      DebugLogger::runtime_print_string func, :rt_scope, "POPPING SCOPE ID : ", scope_val, "\n"
      DebugLogger::runtime_print_string func,
         :rt_runtime_curr_id_trace, "calling a popped return continuation #{caller.first} : {", bouncer, "}\n"
      d = Dispatch.new bouncer
      d.scope_val = scope_val
      do_dispatch func, mem_ctx, d
   end

   def dispatch_to_next func, mem_ctx, next_ast_path, ast_order, curr_id, num_params
      skip_data_inspect = nil
      if (next_ast_path.nil? and ast_order != @ast_order) or (next_ast_path == false)
         skip_data_inspect = false
         gen_return func, mem_ctx
         return
      elsif next_ast_path.is_a? Value
         skip_data_inspect = false
         next_point_val = next_ast_path
      else
         skip_data_inspect = should_skip_data_inspect? next_ast_path
         next_curr_id = @crawler.path2id next_ast_path 
         next_point_val = next_curr_id 
         idbg(:dbg_build_function_inner) {
            "going to er #{next_curr_id} (#{@crawler.find_path_sexp(next_ast_path).inspect[0..40]}) next"
         }
         if [:defn_hacked].include? sexptype(@crawler.find_path_sexp(next_ast_path))
            idbg(:dbg_build_function_inner) { red("WOWZERS ARGH!!!!! :( ") + green("BLAAAAAAAAAAAAH!!!!!! :(:(:(") }
            skip_data_inspect = false
            gen_return func, mem_ctx
         end
      end
      dispatch_to_id_value func, mem_ctx, next_point_val, curr_id, num_params || -1, skip_data_inspect
   end

   def build_as_much_as_predictable mem_ctx, curr_id, prev_id, got_num_params, func
      next_ast_path, num_params, ast_order = nil, nil, nil
      idbg(:node_predict) { "starting yay with #{curr_id} and previous was #{prev_id}" }
      just_did_export = false
      ts = TreeState.new @crawler, @path2anon_block, curr_id
      export_vars_list, export_special_vars, is_anon_block = find_export_vars ts
      created_scope = false
      if !export_vars_list.nil?
         unless is_anon_block
            mem_ctx.locals_dict.scope_ast_id = curr_id
            mem_ctx.locals_dict.needs_new_scope = true
            ProfFuncWithMd::md_made_scope func
            created_scope = true
         end
         export_vars func, mem_ctx, export_vars_list, export_special_vars, got_num_params, curr_id, is_anon_block 
         num_vars = (export_vars_list+export_special_vars).length
         if @build_hints && @build_hints.opt_call_dst
            if dbg_on :rt_call_param_opt
               puts "BUILDING OPTIMAL [POP] (#{num_vars}) ROUTE #{curr_id} - #{caller.inspect}"
               DebugLogger::runtime_print_string func, "[OPTIMAL] (#{curr_id}) exporting #{num_vars} vars\n" 
            end
         else 
            if dbg_on :rt_call_param_opt
               puts "BUILDING NON OPTIMAL [POP] (#{num_vars}) ROUTE #{curr_id} - #{caller.inspect}"
               DebugLogger::runtime_print_string func, "[normal] (#{curr_id}) exporting #{num_vars} vars\n" 
            end
         end
         just_did_export = true
      end
      mem_ctx.locals_dict.load_current_scope if curr_id >= 0 and !created_scope
      loop {
         idbg(:node_predict) { "... continuing yay with #{curr_id} and previous was #{prev_id}" }
         @func_ids << curr_id
         curr_id, next_ast_path, num_params, ast_order = \
            build_function_inner_inner mem_ctx, curr_id, prev_id, got_num_params, func, just_did_export, ts \
            unless curr_id == FINISHED
         gen_data_inspect func, mem_ctx if $data_inspect_every_node
         if curr_id == FINISHED 
            idbg(:dbg_build_function_inner) { "got a curr_id of #{curr_id} yay!, we're finished!" }
            func.insn_return NN::mk_constant(func, :int, -1)
         elsif (next_ast_path.nil? and ast_order == @ast_order)
            gen_return func, mem_ctx
         else
            if !@calling_function
               mem_ctx.locals_dict.force_creation
            end
            dispatch_to_next func, mem_ctx, next_ast_path, ast_order, curr_id, num_params
         end
         made_scope = ProfFuncWithMd::md_made_scope? func
         ProfFuncWithMd::md_unset_made_scope func
         initial_state = (@scope_linkage.keys.size == 1 and @scope_linkage[@scope_linkage.keys.first].empty?)
         if initial_state 
            initial_id = @scope_linkage.keys.first
            @scope_linkage[initial_id] += [initial_id, INITIAL_PREV]
         end
         chain_to = nil
         if !(@scope_linkage.has_key? curr_id)
            if made_scope and !initial_state
               lookup_chain_on_id = curr_id
               pair_to_chain_to = @scope_linkage.detect { |(k,v)| v.include? lookup_chain_on_id }
               if pair_to_chain_to.nil?
                  chain_to = [curr_id]
                  @scope_linkage[curr_id] = chain_to 
                  idbg(:scope_linking) {
                     "trying to make a new scope, ended up with #{@scope_linkage.inspect}"
                  }
               else
                  idbg(:scope_linking) {
                     "skipping creation of a new scope as #{@scope_linkage.inspect} already has #{prev_id} in it!"
                  }
               end
            else
               lookup_chain_on_id = initial_state ? @scope_linkage.keys.first : prev_id
               pair_to_chain_to = @scope_linkage.detect { |(k,v)| v.include? lookup_chain_on_id }
               idbg(:scope_linking) { "looking up on #{lookup_chain_on_id}, @scope_linkage = #{@scope_linkage.inspect}" }
               if !pair_to_chain_to.nil?
                  chain_to = pair_to_chain_to[1]
               elsif lookup_chain_on_id != INITIAL_PREV
                  puts "erm, oops?, we didn't find anything for #{lookup_chain_on_id} in #{@scope_linkage.inspect}"
                  exit
               end
            end
         end
         idbg(:scope_linking) { "WANT TO CONNECT #{prev_id} WITH #{curr_id}, and erm. " +
                                "made_scope == #{made_scope} - chaining it to #{chain_to.inspect}, but like, can we?" }
         chain_to << curr_id if !chain_to.nil? and !chain_to.include? curr_id
         idbg(:scope_linking) { "ended up with: #{@scope_linkage.inspect}" }
         if !@predicting_next_id.empty?
            idbg(:node_predict) { "got next id == #{curr_id.inspect}" }
         else
            idbg(:node_predict) { "no prediction, lets quit on #{curr_id}" }
            idbg(:scope_linking) { "are we missing #{curr_id} somehow???" }
            break
         end
         prev_id = curr_id 
         curr_id = @predicting_next_id.shift
         ts = TreeState.new @crawler, @path2anon_block, curr_id
      }
      idbg(:node_predict) { "node prediction has finished" }
   end

   def make_stack func, size, initial_position
      fail "sorry, but the size is stored at position 0!" if initial_position == 0
      all_locals_mem = NN::mk_bytearray(func, size) # struct: length, (id, value)*
      func.insn_store_elem all_locals_mem, NN::mk_constant(func, :int, 0), NN::mk_constant(func, :int, initial_position) # set position
      all_locals_mem 
   end

   # passage
   def build_setup_func_init func, mem_ctx
      func.create_with_prototype :int, []
      mem_ctx.stack_mem        = make_stack(func, 8 * 1024 * 100, 100)
      mem_ctx.return_stack_mem = make_stack(func, 4 * 4096 * 100, 1)
      mem_ctx.all_locals_mem   = make_stack(func, 20 * 3 * 1024 * 100 + 1, 32)
      finished_bouncer = mk_bouncer FINISHED, -1, -1, func
      stack = RbStack.new func, mem_ctx.stack_mem, :alt
      stack.push NN::mk_constant(func, :ptr, finished_bouncer), NN::mk_constant(func, :int, 0) # -> pre3 == 0
      dummy, orig_scope_id = create_new_scope func, mem_ctx, OUTER_SCOPE
      # setup scope cache
      # # TODO - use FieldDesc's
      func.insn_store_elem mem_ctx.stack_mem, NN::mk_constant(func, :int, 1), orig_scope_id
      func.insn_store_elem mem_ctx.stack_mem, NN::mk_constant(func, :int, 2), 
         NN::mk_constant(func, :int, 0)  # set loaded_scope
      func.insn_store_elem mem_ctx.stack_mem, NN::mk_constant(func, :int, 3),
         NN::mk_constant(func, :int, -1) # set loaded_scope_id
      # setup indirections
      indirections = make_stack(func, 2**16, 1)
      func.insn_store_elem mem_ctx.stack_mem, NN::mk_constant(func, :int, 4), indirections
      ProfFuncWithMd::md_force_data_inspect func
      bouncer = generate_continuation_bouncer(NULL_BLOCK, NULL_BLOCK, -1, func) # a single multi-arg
      new_indirection_block(func, mem_ctx, bouncer) # should be at position 1
      # cache the packed null block
      position_on_stack, scope = NN::mk_constant(func, :int, 1), NN::mk_constant(func, :int, -555)
      packed_null_block = pack_block(func, position_on_stack, scope)
      func.insn_store_elem mem_ctx.stack_mem, NN::mk_constant(func, :int, 5), packed_null_block 
      # generated scope cache
      scopescache = make_stack(func, 2**10, 1)
      func.insn_store_elem mem_ctx.stack_mem, NN::mk_constant(func, :int, 6), scopescache
      # logging a trace of calls into a stack
      trace_stack_ptr = make_stack(func, 2**16, 1)
      func.insn_store_elem mem_ctx.stack_mem, NN::mk_constant(func, :int, 7), trace_stack_ptr
      func.insn_store_elem mem_ctx.stack_mem, NN::mk_constant(func, :int, 8), NN::mk_constant(func, :ptr, func)
      trace_stack = RbStack.new func, trace_stack_ptr, :alt
   end

   CURRENT_SCOPE_ID_IDX = 1

   def build_main_func_init func, mem_ctx, curr_id
      params = []
      func.create_with_prototype ATOM_RET_VAL, construct_prototype_of_length(params.length)
      func.fill_value_with_param mem_ctx.stack_mem,        STACK_BYTEARRAY_PARAM_IDX
      func.fill_value_with_param mem_ctx.return_stack_mem, RETURN_STACK_BYTEARRAY_PARAM_IDX
      func.fill_value_with_param mem_ctx.all_locals_mem,   ALL_LOCALS_BYTEARRAY_PARAM_IDX
      params.each_with_index {
         |param, idx|
         func.fill_value_with_param param, (ALL_LOCALS_BYTEARRAY_PARAM_IDX + 1 + idx)
      }
      params.each {
         |param|
         DebugLogger::runtime_print_string func, "got param : ", param, "\n"
      }
      if check_dbg(:rt_scope)
         current_scope_id = Value.new
         func.insn_load_elem current_scope_id, mem_ctx.stack_mem, 
            NN::mk_constant(func, :int, CURRENT_SCOPE_ID_IDX), :int
         DebugLogger::runtime_print_string func, "CURRENT SCOPE ID : ", current_scope_id, "\n"
      end
      params
   end

   def build_function_inner curr_id, prev_id, got_num_params, initialisation, func
      @skip_data_inspect = true
      mem_ctx = nil
      passed_params = nil
      if initialisation
         mem_ctx = MemContext.new nil, nil, nil, nil
         func.mem_ctx = mem_ctx
         build_setup_func_init func, mem_ctx
         passed_params = []
         ProfFuncWithMd::md_init_init_func func
         ProfFuncWithMd::md_mark_not_real func
      else
         mem_ctx = MemContext.new Value.new, Value.new, Value.new, nil
         func.mem_ctx = mem_ctx
         passed_params = build_main_func_init func, mem_ctx, curr_id
      end
      old_func_ptr = Value.new
      # 8 == new, 9 == old
      func.insn_load_elem old_func_ptr, mem_ctx.stack_mem, NN::mk_constant(func, :int, 8), :void_ptr
      func.insn_store_elem mem_ctx.stack_mem, NN::mk_constant(func, :int, 9), old_func_ptr
      func.insn_store_elem mem_ctx.stack_mem, NN::mk_constant(func, :int, 8), NN::mk_constant(func, :ptr, func)
      mem_ctx.return_rbstack = RbStack.new func, mem_ctx.return_stack_mem, :ret, true
      mem_ctx.locals_dict = DictLookup.new(self, func, @scope_linkage, mem_ctx)
      # TODO - don't add label when there will be no static dispatch
      atom_main_label = Label.new
      func.insn_label atom_main_label
      ProfFuncWithMd::md_set_atom_main_label func, atom_main_label 
      if curr_id == FORCED_POP
         gen_return func, mem_ctx
      else
         build_as_much_as_predictable mem_ctx, curr_id, prev_id, got_num_params, func
      end
   end
   
   def id2name value
      ID_CONSTANTS.detect { |id| value == self.class.const_get(id) } || value
   end

   attr_reader :func_cache

   def hack_static_ptr dest_func, new_ref
      dispatch_id  = new_ref[0]
      dispatch_pos = new_ref[1]
      if not @func_cache.has_key? dispatch_id
         puts "failure to hack up pointer #{dispatch_id}!"
         exit
      end
      impl = dest_func
      impl.pos = dispatch_pos
      inst = impl.instr
      fail "horrribblyyyy" if inst[0] != 21 # CCB
      new_dispatch_func = @func_cache[dispatch_id].func
      new_func_ptr_value = NN::mk_constant(impl, :ptr, new_dispatch_func)
      ret_val, old_func_ptr, ret_val_type, prototype, params = *inst[1..-1]
      impl.insn_call_indirect_vtable_blah ret_val, new_func_ptr_value, ret_val_type, prototype, params
      impl.pos = dispatch_pos
   end

   # update all static dispatches that refer to this one
   # optimisation
   def update_static_dispatches curr_id
      idbg(:specialisation) { cyan("!!!!!!!!!!")+magenta("CHECK")+cyan("!!!!!!!!!!") + " #{curr_id}}" }
      each_static_dispatcher(curr_id) {
         |cached_func, dispatch|
         idbg(:specialisation) { green("updating") + " #{cached_func} -> #{dispatch.inspect}" }
         hack_static_ptr cached_func, dispatch
      }
   end

   # optimisation framework
   def each_static_dispatcher curr_id
      @old_functions.each {
         |cached_func|
         static_dispatches = ProfFuncWithMd::md_get_statically_dispatches_to cached_func
         next if static_dispatches.nil?
         static_dispatches.each {
            |dispatch|
            next if dispatch[1].nil? # direct branch rather than static dispatch
            yield cached_func, dispatch
         }
      }
   end

   # optimisation
   def slow_dispatch_needs_rebuild? cached_func
      return false unless (ProfFuncWithMd::md_get_slow_dispatches cached_func.func)
      idbg(:specialisation) { magenta("SLOW DISPATCH IN [#{cached_func.inspect}]") }
      rebuild = false
      (ProfFuncWithMd::md_get_slow_dispatches cached_func.func).each { 
         |slow_id| 
         cached = @func_cache.has_key? slow_id
         cursor = AstCursor.new slow_id
         used = cursor.id_hit? @old_functions
         if cached
            # we can go ahead with a rebuild if its cached anyway
            idbg(:specialisation) { "#{slow_id} -> cached" }
            rebuild = true
         elsif !cached and used
            # if its uncached and its used, we should rebuild as we can change a slow into a static via the rebuild
            idbg(:specialisation) { "#{slow_id} -> !cached and used" }
            rebuild = true
         elsif !cached and !used
            # if its not used, then there is no reason to rebuild
            idbg(:specialisation) { "#{slow_id} -> !cached and !used" }
         end
         idbg(:specialisation) { "#{slow_id} -> #{rebuild}" }
      }
      idbg(:specialisation) { magenta("WE'RE GONNA REBUILD? - #{rebuild}") }
      rebuild
   end

   # optimisation framework
   def static_continuation_point_older? cached_func
      return false unless (ProfFuncWithMd::md_get_static_continuation_point cached_func.func)
      cp = (ProfFuncWithMd::md_get_static_continuation_point cached_func.func).first
      if @func_cache[cp].func.metadata[:build_time] > cached_func.func.metadata[:build_time]
         idbg(:specialisation) { "OLDER! -> " }
         return true
      else
         return false
      end
   end

   # generation
   def rebuild_id_set rebuild_ids
      already_built = {}
      rebuild_ids.each {
         |rebuild_info|
         id    = rebuild_info.id
         next if already_built.has_key? id
         count = rebuild_info.hit_count
         if count.nil?
            # generate_rebuild_list fills this field in, you can feel free to leave empty however
            cursor = AstCursor.new id
            count = cursor.id_hit? @old_functions, true
         end
         cached_func = @func_cache[id].func
         num_params = (ProfFuncWithMd::md_get_num_params cached_func)
         prev_id = (ProfFuncWithMd::md_get_prev_id cached_func)
         was_generated_by = (ProfFuncWithMd::md_get_was_generated_by cached_func)
         @func_cache.delete id
         cached_func = nil
         @build_hints = rebuild_info.hints
         build_function id, prev_id, num_params, was_generated_by, false
         @build_hints = nil
         new_func = @func_cache[id].func
         ProfFuncWithMd::md_inc_rebuild_count new_func
         ProfFuncWithMd::md_set_last_hit_count new_func, count
         already_built[id] = nil
      }
      already_built.keys
   end

   RebuildTask = Struct.new(:id, :hit_count, :hints)

   # opt framework
   def generate_rebuild_list condition_block, executed_block
      rebuild_ids = []
      @func_cache.each_pair {
         |id, func|
         next if !condition_block.call id, func
         # should we bother? did we get hit more?
         cursor = AstCursor.new id
         count = cursor.id_hit? @old_functions, true
         cached_func = @func_cache[id].func
         old_hit_count = (ProfFuncWithMd::md_get_last_hit_count cached_func)
         if old_hit_count != count 
            # " + (ProfFuncWithMd::md_inspect cached_func.func.metadata) + " (#{id})
            executed_block.call "#{id} }(#{old_hit_count} != #{count})", id
            rebuild_ids << RebuildTask.new(id, count)
         end
      }
      rebuild_ids
   end

   def split8 str
      str.scan(/.{8}/m)
   end

   def split12 str
      str.scan(/.{12}/m)
   end

   Dissection = Struct.new :offs, :dat, :addr, :len

   # sidenote:
   # what if first_id != the id at which the optimisation was done???
   # optimisation
   def update_indirections 
      rebuild_ids = []
      ind = dissect_indirections @indirections_addr
      indirections_addr_offs, indirections_dat, indirections_addr = ind.offs, ind.dat, ind.addr
      indirections_dat.each  {
         |str|
         # update this dummy is the compile time ref! - 
         #  store the index into the indirections array vs the compile time ref!
         ptr_addr, dummy = str.unpack("iI")
         func1 = Value.addr2func ptr_addr
         first_id   = (ProfFuncWithMd::md_get_next_id func1)
         first_id ||= ProfFuncWithMd::md_get_path_range(func1).first
         idbg(:indirection_specialisation) {
            "got #{Value.addr2func ptr_addr} - #{dummy}, with id #{first_id.inspect}"
         }
         replacement = @func_cache[first_id]
         if !replacement.nil? && func1 != replacement.func
            idbg(:indirection_specialisation) {
               "updating #{func1.metadata.inspect}: with #{ProfFuncWithMd::md_inspect replacement.func.metadata}"
            }
            replc_ptr_addr = Value.func2addr(replacement.func)
            Value.stringpoke(indirections_addr + indirections_addr_offs, [replc_ptr_addr, first_id].pack("iI"), 8)
            condition_block = proc {
               |id, func|
               return false if ProfFuncWithMd::md_get_creates_bouncer_to(func.func).nil?
               return false unless ProfFuncWithMd::md_get_creates_bouncer_to(func.func).include? first_id
               true
            }
            executed_block = proc {
               |description, id|
               idbg(:indirection_specialisation) { magenta("re-gen #{description} - currently has old bouncer gen") }
            }
            rebuild_ids += generate_rebuild_list condition_block, executed_block
         end
         indirections_addr_offs += 8
      }
      rebuild_id_set rebuild_ids
   end

   attr_reader :trace_stack_history

   def import_from_trace_stack
      return nil if @trace_stack_addr.nil?
      trace_stack = dissect_trace_stack @trace_stack_addr
      Value.stringpoke(@trace_stack_addr, [1].pack("i"), 4)
      @trace_stack_history ||= []
      @trace_stack_history << trace_stack 
      trace_stack
   end

   def trace_stack_iterator trace_stack_dat
      trace_stack_dat.each {
         |str|
         new_func_ptr, old_func_ptr = str.unpack("II")
         old_func = Value.addr2func old_func_ptr
         new_func = Value.addr2func new_func_ptr
         yield old_func, new_func 
      }
   end

   # optimisation
   def find_param_stack_flattening_possibilities dispatch_id_list
      trace_stack = import_from_trace_stack
      return if trace_stack.nil?
      call_func, method_func = nil, nil
      expecting_continuation = false
      call_triplets = []
      trace_stack_dat = trace_stack.dat
      trace_stack_dat += @last_trace_stack.dat if @last_trace_stack
      trace_stack_iterator(trace_stack_dat) {
         |old_func, new_func|
         elt_id = ProfFuncWithMd::md_get_path_range(new_func).first
         elt_path = @crawler.id2path elt_id
         matching_func_def = @func_defs.values.detect { |order| (elt_path == order.first) }
         if expecting_continuation
            cont_func = new_func
            cont_point = ProfFuncWithMd::md_get_static_continuation_point(call_func)
            if cont_point && (cont_point.first == ProfFuncWithMd::md_get_path_range(cont_func).first)
               expecting_continuation = false
               # this next line is fuzzy... whats the actual cause of a nil here? is the name correct?
               some_already_rebuilt_funcs = [call_func, method_func, cont_func].detect { 
                  |func|
                  @func_cache[ProfFuncWithMd::md_get_id(func)].nil?
               }
               missing_type_caching = (not @node2type_cache.has_key?(ProfFuncWithMd::md_get_id(method_func)))
               if !some_already_rebuilt_funcs 
                  call_triplets << Struct.new(:call, :method, :cont).new(call_func, method_func, cont_func)
                  next
               end
            end
         end
         if !matching_func_def.nil?
            call_func, method_func = old_func, new_func
            expecting_continuation = true
         end
      } if !trace_stack.nil?
      rebuild_ids = []
      call_triplets.each {
         |triplet|
         tmp = []
         tmp << RebuildTask.new(ProfFuncWithMd::md_get_id(triplet.cont),   nil, Hints.new(:opt_call_cnt=>1))
         tmp << RebuildTask.new(ProfFuncWithMd::md_get_id(triplet.method), nil, Hints.new(:opt_call_dst=>1))
         tmp << RebuildTask.new(ProfFuncWithMd::md_get_id(triplet.call),   nil, Hints.new(:opt_call_src=>1))
         rebuild_ids << tmp
         puts magenta("FOUND AN OPTIMAL ROUTE #{[
                        ProfFuncWithMd::md_get_id(triplet.cont),
                        ProfFuncWithMd::md_get_id(triplet.method),
                        ProfFuncWithMd::md_get_id(triplet.call)
                      ].inspect}")
      }
      rebuilt, done = [], []
      @triplet_rebuild_lists ||= []
      @triplet_rebuild_lists += rebuild_ids
      @triplet_rebuild_lists.each {
         |triplet|
        puts "CHECKING TRIPLETS"
         # next line is just to make CERTAIN that we don't build out of order...
         next if triplet.detect { |task| task.hints.opt_call_dst && (task.id == @current_execution_id) }
         if missing = triplet.detect { |task| not (@func_cache.has_key? task.id) }
            fail "missing #{missing}! so we can't even build the triplets wtf?"
         end
         puts "trying to rebuild -> #{triplet.map {|obj| obj.id}.inspect}"
         rebuilt = rebuild_id_set triplet
         puts "rebuild done"
         dispatch_id_list += rebuilt
         dispatch_id_list.replace(@func_cache.keys)
         fail "possible duplicate static update" if dispatch_id_list.sort.uniq.length != dispatch_id_list.length
         done << triplet
      }
      @triplet_rebuild_lists.reject! { |triplet| done.include? triplet }
      @last_trace_stack = trace_stack
      (!rebuilt.empty?)
   end

   # optimisation
   def find_scope_templating_possiblities
      #   puts "looking for find_scope_templating_possiblities"
      condition_block = proc {
         |id, func|
         return false unless ProfFuncWithMd::md_lookups(func.func) \
                        and !ProfFuncWithMd::md_lookups(func.func).empty?
         true
      }
      executed_block = proc {
         |description, id|
         idbg(:rebuild) { "GENERATING #{description} AS SCOPE TEMPLATE CHANGED!" }
      }
      rebuild_ids = generate_rebuild_list condition_block, executed_block
      rebuilt = rebuild_id_set rebuild_ids
      (!rebuilt.empty?)
   end

   # optimisation
   def attempt_specialization atom, curr_id
      idbg(:indirection_specialisation) { "****\n" + magenta("ARGH ITS THE SPECIALISATION YAY ARGH OOO") }
      to_be_specialized = (ProfFuncWithMd::md_get_next_ids atom.func).detect {
         |next_id| @node2type_cache.has_key? next_id
      }
      to_be_specialized = true if (@node2type_cache.has_key? curr_id)
      if (ProfFuncWithMd::md_has_slow_dispatches atom.func)
         rebuild = false
         # we don't care about slow_id's that haven't been used before anyway,
         # as they won't affect the overall execution until they *have* been
         # used. and at this point we can backtrack and rebuild this. thusly,
         # we are only interested in not rebuilding, if there are any slow_id's
         # that *have* been executed before
         (ProfFuncWithMd::md_get_slow_dispatches atom.func).each {
            |slow_id|
            cursor = AstCursor.new slow_id
            if cursor.id_hit? @old_functions
               idbg(:indirection_specialisation) { "want to rebuild cus like #{slow_id} is used" }
               rebuild = true 
               break
            end
         }
         to_be_specialized = true if rebuild
      end
      curr_id_included = false
      condition_block = proc {
         |id, func|
         return false unless (static_continuation_point_older? func) || (slow_dispatch_needs_rebuild? func)
         true
      }
      executed_block = proc {
         |description, id|
         idbg(:rebuild) { "CHECKING CACHED FUNCTION #{description}" }
         curr_id_included = true if id == curr_id
      }
      rebuild_ids = generate_rebuild_list condition_block, executed_block
      rebuilt = rebuild_id_set rebuild_ids
      # the above also caused regen of curr_id,
      # so we only specialize if this wasn't the case, otherwise we re-gen twice!  
      to_be_specialized = false if curr_id_included
      atom = @func_cache[curr_id]
      idbg(:specialisation) { cyan("!!!!!!!!!!")+magenta("REBUILDING") + "!!! SHOULD BE FINISHED NOW!" }
      if to_be_specialized
         idbg(:func_cache) { "NOT USING CACHE AS SPECIALISATION AWAITS FOR - " \
                           + "#{@node2type_cache[ProfFuncWithMd::md_get_next_ids(atom.func).first]}" }
      end
      to_be_specialized
   end

   # flow
   def generate_func curr_id, prev_id, got_num_params, caller_func, initialisation
      idbg(:build_function) { "GENERATING FUNCTION #{id2name curr_id}" }
      notes = { :next_ids => [], :assumptions => [], :was_generated_by => caller_func }
      func = ProfilingFunction.new @context
      func.metadata = notes
      func.metadata[:hints] = @build_hints # FIXME
      @old_functions << func
      @predicting_next_id = []
      @func_ids = []
      ProfFuncWithMd::md_set_path_range(func, @func_ids) # NOTE - can be empty in the case of exit path
      func.lock { 
         idbg(:func_cache) { green("current:#{curr_id}, prev:#{prev_id}, num_params:#{got_num_params}") }
         build_function_inner curr_id, prev_id, got_num_params, initialisation, func
         func.compile
      }
      # todo - following should be limited
      func.metadata[:prev_id] = prev_id
      func.metadata[:num_params] = got_num_params
      add = func.metadata[:assumptions].empty?
      add = false if ProfFuncWithMd::md_has_init_func func
      first_id = @func_ids.first
      will_add = (add and !@func_ids.empty? and first_id >= 0)
      idbg(:func_cache) { 
         assumptions = ProfFuncWithMd::md_get_assumptions(func).inspect
         notes = ProfFuncWithMd::md_inspect func.metadata
         (will_add ? cyan("ADDING") : magenta("NO ADD OF")) + 
         " range #{@func_ids.inspect} TO CACHE - assumptions == #{assumptions} - notes == #{notes}" 
      }
      if will_add
         new_atom = Struct.new(:func).new(func)
         func.metadata[:build_time] = Time.now
         @func_cache[first_id] = new_atom
      end
      func
   end

   # logging
   $next_postproc = nil
   def my_callback my_string
      line = my_string.chomp
      str = nil
      if !$next_postproc.nil?
         str = $next_postproc.call(line.to_i)
         $next_postproc = nil
      elsif $message_hash.has_key? line.to_i
         $next_postproc = $message_hash_post_proc[line.to_i]
         str = $message_hash[line.to_i]
      else
         str = line
      end
      if !str.nil? and !str.empty?
         if str == "BREAKPOINT CALLBACK\n"
            self.instance_eval { breakpoint("breakpoint was called!") }
         end
         $str_buffer << str
      end
   end

   # passage
   def typeval2desc bytes
      type = Typing::ID_MAP.index bytes[4,4].unpack("I").first
      [type, bytes[0,4].unpack("i").first]
   end

   # passage
   def dissect_indirections indirections_addr
      indirections_len = Value.ptr2string(indirections_addr, 4).unpack("i").first
      indirections_dat = split8 Value.ptr2string(indirections_addr + 2*4, indirections_len * 4)
      indirections_addr_offs = 2*4
      Dissection.new(indirections_addr_offs, indirections_dat, indirections_addr, indirections_len)
   end

   def dissect_trace_stack trace_stack_addr
      trace_stack_len = Value.ptr2string(trace_stack_addr, 4).unpack("i").first
      trace_stack_dat = split8 Value.ptr2string(trace_stack_addr + 2*4, trace_stack_len * 4)
      trace_stack_addr_offs = 2*4
      Dissection.new(trace_stack_addr_offs, trace_stack_dat, trace_stack_addr, trace_stack_len)
   end

   # passage
   # appends a new scopescache element
   def cache_scope scopescache_addr, symbols
      scopescache_len = Value.ptr2string(scopescache_addr, 4).unpack("i").first
      scopescache_addr_offs = 1*4
      sym_string = symbols.map { |sym| [sym.to_i, 0, 0].pack "III" }.join
      scope_string = [symbols.length].pack("I") + sym_string 
      ptr = Value.bytearray2ptr scope_string.dup
      Value.stringpoke(scopescache_addr + scopescache_addr_offs * (1 + scopescache_len), [ptr].pack("I"), 4)
      Value.stringpoke(scopescache_addr, [scopescache_len+1].pack("I"), 4)
      return scopescache_len + 1, (symbols.length * 3) + 1
   end

   # passage
   def dissect_stack_mem ptr1
      # TODO - this works, however is it really correct?
      stack_mem_len        = (Value.ptr2string(ptr1, 4).unpack("i").first - 2 - 95) / 2
      stack_mem            = split8 Value.ptr2string(ptr1 + (6+95)*4, 4 * (stack_mem_len * 2))
      Dissection.new((4+95)*4, stack_mem, ptr1, stack_mem_len)
   end

   # passage
   def dissect_return_stack_mem ptr2
      return_stack_mem_len = (Value.ptr2string(ptr2, 4).unpack("i").first - 1) / 2
      return_stack_mem     = if return_stack_mem_len > 0
                              split8(Value.ptr2string(ptr2 + 2*4, 4 * (return_stack_mem_len * 2)))
                           else
                              []
                           end
      Dissection.new 2*4, return_stack_mem, ptr2, return_stack_mem_len 
   end

   # passage
   def dissect_all_locals_mem ptr4
      # original position == 2 # 32 is our offset
      all_locals_mem_len   = (Value.ptr2string(ptr4, 4).unpack("i").first - 32) / 2
      all_locals_mem       = split8 Value.ptr2string(ptr4 + 4 + 32 * 4, 4 * (2 * all_locals_mem_len))
      Dissection.new 4 + 32 * 4, all_locals_mem, ptr4, all_locals_mem_len
   end

   # passage
   def my_data_inspect ptr1, ptr2, ptr3, ptr4
      bench("data_inspect") {
         @trace_stack_addr  = Value.ptr2string(ptr1 + 7*4, 4).unpack("I").first
         @indirections_addr = Value.ptr2string(ptr1 + 4*4, 4).unpack("I").first
         @scopescache_addr  = Value.ptr2string(ptr1 + 6*4, 4).unpack("I").first
         current_scope_id   = Value.ptr2string(ptr1 + 1*4, 4).unpack("i").first
         ind = dissect_indirections @indirections_addr
         indirections_len = ind.len
         dissected_stack_mem = dissect_stack_mem(ptr1) if dbg_on :data_inspect

         return_stack_mem_dissection = dissect_return_stack_mem ptr2
         return_stack_mem_translated = return_stack_mem_dissection.dat.map { |bytes| typeval2desc bytes } \
            if dbg_on :data_inspect

         receiver_object = return_stack_mem_dissection.dat.last # self
         @object = receiver_object.nil? ? nil : typeval2desc(receiver_object)

         all_locals_mem_dissection = dissect_all_locals_mem ptr4
         if $opt_scope_templates or dbg_on :data_inspect
            all_locals_mem_translated = all_locals_mem_dissection.dat.map {
               |bytes|
               locals_addr, scope_ast_id = bytes.unpack "Ii"
               # locals_mem == size, n * (id / value / type)
               size = Value.ptr2string(locals_addr, 4).unpack("i").first 
               locals_mem = split12 Value.ptr2string(locals_addr + 4, 4 * ((size * 3)))
               scope = []
               locals_mem.map! {
                  |bytes|
                  sym_id = bytes[0,4].unpack("I").first
                  scope << sym_id.id2name.to_sym
                  [sym_id.id2name, typeval2desc(bytes[4,8])]
               }
               if $opt_scope_templates and @scope_hash[scope_ast_id] and !scope.empty?
                  if scope != @scope_hash[scope_ast_id]
                     cur_template = @scope_hash[scope_ast_id]
                     # scope - the new one, cur_template - the old one, 
                     missing = scope - (scope & cur_template)
                     min_matching_prefix_len = [cur_template.size, scope.size].min
                     matching_prefix = (cur_template.slice(0...min_matching_prefix_len) \
                                     == scope.slice(0...min_matching_prefix_len))
                     idbg(:scope_templates) {
                        "trying to add #{scope.inspect} to #{@scope_hash[scope_ast_id].inspect}, "
                      + "thusly the diff is -> #{missing.inspect}"
                     }
                     if !matching_prefix
                        matching = scope.slice(0..cur_template.length).inspect
                        puts "#{cur_template.inspect} VS #{matching} of #{scope.inspect}"
                        fail "prefix doesn't match!!!! its all wrong, we all cry!"
                     end
                     @scope_hash[scope_ast_id] += missing
                     idbg(:scope_templates) {
                        "adding (#{missing.inspect}) to a scope!!! - #{scope.inspect} :" +
                        "making for the current scope_hash of #{@scope_hash.inspect}"
                     }
                  end
               elsif !scope.empty?
                  idbg(:scope_templates) { "found a scope!!! - #{scope.inspect} - #{scope_ast_id}" }
                  @scope_hash[scope_ast_id] = scope
               end
               [scope_ast_id, locals_addr, locals_mem]
            }
         end

         @self_type = nil
         catch(:done) {
            all_locals_mem_dissection.dat.each_with_index {
               |bytes, idx|
               locals_addr, scope_ast_id = bytes.unpack "Ii"
               scope_id = (32 + 2*idx)
               next unless scope_id == current_scope_id
               # locals_mem == size, n * (id / value / type)
               size = Value.ptr2string(locals_addr, 4).unpack("i").first
               locals_mem = split12 Value.ptr2string(locals_addr + 4, 4 * ((size * 3)))
               locals_mem.each {
                  |bytes|
                  sym_id = bytes[0,4].unpack("I").first
                  if sym_id.id2name.to_sym == :__self__
                     @self_type = typeval2desc(bytes[4,8])[0]
                     throw :done
                  end
               }
            }
         }

         idbg(:data_inspect) {
            stack_mem_dump = dissected_stack_mem.dat.map {
               |bytes| t = bytes.unpack("ii"); "[MEM:#{t[0]}, #{t[1]}]" }
            all_locals_mem_dump = #{all_locals_mem_translated.map{|locals|locals.inspect}.join("\n").indent 6
            <<DBG
   OBJECT == #{@object.inspect}
   current_scope_id == #{current_scope_id.inspect}
   stack_mem        == #{dissected_stack_mem.len.to_s} #{stack_mem_dump}
   return_stack_mem == #{return_stack_mem_dissection.len.to_s} #{return_stack_mem_translated.inspect}
   all_locals_mem   == #{all_locals_mem_dissection.len.to_s} \n#{all_locals_mem_dump}
   indirections_len == #{indirections_len}
DBG
         }
      }
   end

   # main flow
   def build_function curr_id, prev_id, got_num_params, caller_func, initialisation
      is_rebuild_magic = !@build_hints.nil?
      @current_execution_id = curr_id unless is_rebuild_magic 
      if !caller_func.nil? and dbg_on :generator_path_information
         puts "################### CALLER == #{caller_func.metadata.inspect}"
         if !(ProfFuncWithMd::md_has_no_bouncer_generated_annotation func)
            puts "################### CALLER BOUNCERS GENERATOR == "
               + "#{(ProfFuncWithMd::md_get_generated_by caller_func).metadata.inspect}"
         end
      end
      total_instructions = @old_functions.inject(0) { |a,func| a + func.instructions_executed }
      @time_vs_instructions_log << [(@execution_started_at - Time.now).to_f, total_instructions]
      sexp_element = @crawler.find_path_sexp @crawler.id2path(curr_id) unless curr_id < 0
      idbg(:build_function) { "BUILDING FUNCTION #{id2name curr_id} :: #{id2name prev_id}" +
                              ":: #{got_num_params} :: #{sexp_element.inspect}" }
      idbg(:func_cache) { "FUNCTION CACHE - relating to element - #{sexp_element.inspect}" }
      atom = @func_cache[curr_id]
      idbg(:func_cache) { "FOUND!!! - #{curr_id} -> #{atom.inspect} checking if should!" } if !atom.nil?
      # special when the found atom doesn't have a next_id thats
      # part of the node2type_cache (see ANN1 for more information)
      # FIXME - this following line is in fact not really "to be specialized" but rather... don't rebuild
      to_be_specialized = false
      static_dispatch_updates = []
      if !atom.nil? and $opt_use_cache
         update_indirections if $opt_indirection_updates
         to_be_specialized = attempt_specialization atom, curr_id
         static_dispatch_updates << curr_id if to_be_specialized 
      end
      to_be_specialized = true if $opt_scope_templates && find_scope_templating_possiblities
      unless is_rebuild_magic 
         if $opt_flatten_param_stack && find_param_stack_flattening_possibilities(static_dispatch_updates)
            to_be_specialized = true 
         end
      end
      static_dispatch_updates.each {
         |dispatch_id|
         update_static_dispatches dispatch_id
      }
      atom = @func_cache[curr_id]
      idbg(:func_cache) { "SHOULD REBUILD #{curr_id}? - #{to_be_specialized }" } if !atom.nil?
      if !atom.nil? and $opt_use_cache and !to_be_specialized
         @func_cache_hits += 1
         return atom.func
      end
      @func_cache_misses += 1
      if !atom.nil? and @build_hints.nil?
         @build_hints = atom.func.metadata[:hints]
      end
      return generate_func(curr_id, prev_id, got_num_params, caller_func, initialisation)
   end

   # main flow
   def execute
      @func_defs, @class_func_defs = {}, {}
      gen_orders
      function = build_function(@crawler.path2id(@ast_order.first), OUTER_SCOPE, -1, nil, true)
      begin
         function.apply []
      rescue NanoVMException => e
         puts $str_buffer
         p e
         dump_instructions e.function
         exit
      end
      StateCache::save_cache(self) if $enable_cache
      if $debug
         print_bm_report
         puts "MISSES : #{@func_cache_misses}, HITS :: #{@func_cache_hits}"
      end
   end
end
