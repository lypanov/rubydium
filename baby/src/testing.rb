require "test/unit"
require "dispatcher.rb"
$enable_cache = false
require "tempfile"

module TestMod

   def do_blah src, expected, expected_counts = nil
      if expected.nil?
         tempfile = Tempfile.new "rblex_test"
         tempfile.write <<EOF
class Object
   def alloc_self
      @data = []
   end
   def set a, b
      @data[a] = b
   end
   def dset a, b
      @data[a] = b
   end
   def dget a
      @data[a]
   end
   def get a
      @data[a]
   end
   def set_self string
      @data = [string.length]
      string.each_byte { |b| @data << b }
   end
end
module Kernel
   def pi integer
      puts integer.to_s
   end
   def putch byte
      Kernel.print byte.chr
   end
end
EOF
         tempfile.write src
         tempfile.close
            expected = `bash -c "ruby #{tempfile.path} 2>&1"`
      end
      $str_buffer = ""
      t = Context.new
      machine = EvalMachine.new t, src
      machine.execute
      if $debug
         puts "OUTPUT:"
         puts $str_buffer
      end
      $boo.each {
         |meth|
         method(meth).call(machine)
      }
      if !$debug
         if expected.is_a? Regexp
            assert_equal [expected, !(expected =~ $str_buffer).nil?], [expected, true]
         else 
            assert_equal expected, $str_buffer
         end
      end
      actual = "actual: [#{machine.number_of_instructions_executed}, #{machine.number_of_generated_instructions}]"
      fail "no expected counts given!, #{actual}" \
         if expected_counts.nil?
      diff = (machine.number_of_instructions_executed-expected_counts[0]).abs
      error_ratio = diff.to_f / machine.number_of_instructions_executed.to_f
      if error_ratio > 0.03
         fail "error perc.: #{(error_ratio * 100).to_i}%, #{actual} vs expected #{expected_counts.inspect}"
      end
      fail "number_of_generated_instructions did not match! #{actual}" \
         if expected_counts[1] != machine.number_of_generated_instructions
   end

   def do_test ctx, string, should_be
      execute_string ctx, string
      assert_equal should_be, $str_buffer
  end

   def fmt machine, tuple, func
      return "initial" if tuple.nil?
      node = machine.crawler.find_path machine.crawler.id2path(tuple[1])
      desc = node.inspect
      pp func
      exit
      "#{tuple[0]} - #{tuple[1]} [#{desc[0..20]}]"
   end

   # TODO items - word ( => ) wrap the hashes / which will eventualy be structs, so, figure out word wrapping for those too

   def dump_null machine
   end
   
   def dump_summary machine
      if $debug
         puts "Total number of instructions in all functions: #{machine.number_of_generated_instructions}"
         puts "Total number of instructions executed: #{machine.number_of_instructions_executed}"
      end
   end

    def self.metadata_dump machine
      puts "Reporting on in cached function metadata"
      machine.func_cache.each_pair {
         |id, atom|
         next unless id.is_a? Integer
         print "IS : #{machine.crawler.paths2orderdesc atom.func.metadata[:path_range].map { |id| machine.crawler.id2path id }}"
         print "JUMPS TO : #{machine.crawler.paths2orderdesc atom.func.metadata[:statically_dispatches_to].map { |(id, pos)| machine.crawler.id2path id }}" if atom.func.metadata[:statically_dispatches_to]
         puts "=> ("
         pp machine.metadata_inspect(atom.func.metadata)
         puts ")"
      }
   end

   def self.dump_max_point machine
      self.metadata_dump machine
      last = 0
      shifted_log = machine.time_vs_instructions_log.slice(1..-1)
      diffs = []
      machine.time_vs_instructions_log.zip(shifted_log) { |arr| a,b = *arr; diffs << (b[1]-a[1]).abs unless b.nil? }
      max_point = diffs.max
      puts "non unique max point! o_O" if diffs.index(max_point) != diffs.rindex(max_point)
      idx = diffs.index max_point 
      puts "LOG"
      p machine.time_vs_instructions_log
      puts "POINT OF MAX"
      p idx
      puts "COUNT DIFFS"
      p diffs
      puts "MAX INFO"
      p machine.time_vs_instructions_log[idx]
      exit if $debug
   end

   def dump_asm machine
      machine.old_functions.each {
         |func|
         dump_instructions func
      }
   end

   def dump_profile machine
      line2count = Hash.new { 0 }
      machine.old_functions.each {
         |func|
         next if func.profile_hash.nil?
         func.profile_hash.each_pair {
            |key,val|
            line = func.metadata[:caller_map][key]
            line2count[line] += val
         }
      }
      require 'pp'
      line2count.inject([]) { |a,(k,d)| a << [k, d] }
      pp line2count.sort_by { |(a,b)| b }
      dump_summary machine
   end

   def dump_graph machine
      nodes = ""
      machine.func_cache.each_pair {
         |id, atom|
         next unless id.is_a? Integer
         atom.func.metadata[:path_range].each {
            |sid|
            curr = [atom.func.object_id, sid]
            nodes << "\"#{fmt machine, curr, atom.func}\" [color=green];"
         }
      }
      machine.import_from_trace_stack
      first_iteration = true
      execution_log = []
      boo = proc {
         |func|
         execution_log << func
      }
      machine.trace_stack_history.each {
         |trace_stack|
         machine.trace_stack_iterator(trace_stack.dat) {
            |old_func, new_func|
            boo.call old_func if first_iteration
            boo.call new_func
            first_iteration = false
         }
      }
      prev = nil
      idx = 0
      execution_log.each {
         |t|
         curr = [t.object_id, machine.md_get_id(t)]
         nodes << "\"#{fmt machine, prev, t}\" -> \"#{fmt machine, curr, t}\" [color=green label=\"#{idx}\"];"
         prev = curr
         idx += 1
      }
      tf = File.open "/tmp/blah.dot", "w"
      desc = "\"#{machine.crawler.paths2orderdesc(machine.ast_order).gsub(/\n\s*#/m,"#").gsub("\n","\\n")}\" [color=blue shape=plaintext];"
      tf.write <<EOF
digraph Viewfile {
node [ style = filled ];
#{nodes}
#{desc}
\"#{machine.source.gsub("\n","\\n")} [shape=plaintext]\"
}
EOF
      tf.close
      `open /tmp/blah.dot`
      exit
   end

end
