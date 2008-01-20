$pure_ruby_backend = false

$graph     = false
$debug     = false
$no_debug  = !$debug
$profile   = false
$show_asm  = false
$nanovm_debug = false
$detail    = false

$boo = [case
when $detail;   :dump_max_point
when $show_asm; :dump_asm
when $profile;  :dump_profile
when !$debug;    :dump_null
else;           :dump_summary; end]

$boo << :dump_graph if $graph

$COLOR = $stdout.tty?

$opt_use_cache           = true
$opt_use_predict         = true
$opt_indirection_updates = true
$opt_scope_templates     = true
$opt_static_dispatches   = true
$opt_static_conts        = true
$opt_flatten_param_stack = false
$clever                  = true

$data_inspect_every_node = false
$force_data_inspect      = false

$debug_logged_cache      = false

$ignore_streams_ALL = {
   :dict_lookup                   => 1,
   :build_function                => 1,
   :prediction                    => 1,
   :dbg_build_function_inner      => 1,
   :dbg_dictlookup                => 1,
   :func_cache                    => 1,
   :build_function_inner_inner    => 1,
   :find_export_vars              => 1,
   :export_vars                   => 1,
   :handle_element                => 1,
#  :self_cache                    => 1,
   :indirection_specialisation    => 1,
   :dbg_handle_call_element       => 1,
   :dbg_post_element              => 1,
   :node_predict                  => 1,
   :gen_return                    => 1,
   :data_inspect                  => 1,
   :dispatch_to_id_value          => 1,
   :rebuild                       => 1,
   :specialisation                => 1,
   :stackify                      => 1,
   :gen_orders                    => 1,
   :dbg_handle_definitions        => 1,
   :create_new_scope              => 1,
   :dbg_eat_unneeded_return_value => 1,
   :rt_runtime_curr_id_trace      => 1,
   :rt_runtime_data_inspect_trace => 1,
#  :rt_primitives                 => 1,
   :rt_push_raw                   => 1,
#  :rt_find_index                 => 1,
   :rt_prefilling                 => 1,
   :rt_bouncer                    => 1,
   :rt_bouncer_runtime            => 1,
   :rt_stack                      => 1,
#  :rt_block                      => 1,
   :rt_assign                     => 1,
   :rt_scope                      => 1,
#  :rt_cache                      => 1,
   :rt_back_insertion             => 1,
   :scope_templates               => 1,
#  :scope_linking                 => 1,
#  :cache_store                   => 1,
}

$ignore_streams_EMPTY = { 
}

$ignore_streams = $ignore_streams_ALL

def check_dbg sym
   $debug && ($ignore_streams.has_key? sym)
end

def idbg stream, *config
   if dbg_on stream
      print yield
      print "\n" unless config.include? :no_newline
   end
end

def dbg_on stream
   ($ignore_streams.has_key? stream and !$no_debug)
end

def killi str
   str.gsub(/\s{#{/\A(\s*)/.match(str).to_a[1].length}}/, '')
end

def color clr, str
   $COLOR ? "\033[0;40;#{clr.to_s}m#{str}\033[0;40;39m" : "[% #{str} %]"
end

def red     str; color 31, str; end
def green   str; color 32, str; end
def cyan    str; color 36, str; end
def magenta str; color 35, str; end
