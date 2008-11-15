def foo tests, filename, module_name, slice_size
groups = []
tests.each_slice(slice_size) {
   |slice|
   groups << slice
}

File.open("/tmp/test.rb", "wb") {
	|t|
	t.write """
require \"#{filename}\"
class Test_Boo < Test::Unit::TestCase
   include #{module_name}
end
tests = #{module_name}.public_instance_methods.grep(/^test_/)
tests.each {
	|method|
	#{module_name}.module_eval {
	   unless ARGV.include? method
	      undef_method(method)
	   end
	}
}
"""
}

File.open("/tmp/Makefile", "wb") {
	|t|
	goals = (0...groups.size).to_a.map { |n| "out#{n}" }.join " "
   t.write """
all: #{goals}
\tcat #{goals}

   """
   t.write """
clean:
\trm -f #{goals}

   """
	groups.each_with_index {
	   |slice, n|
      t.write """
out#{n}: #{filename}
\truby /tmp/test.rb #{slice.join " "} > out#{n}
"""
   }
}

system("make -f /tmp/Makefile clean; make -j3 -f /tmp/Makefile")
end

require "../tests/basic.rb"
require "../tests/big.rb"
require "../tests/perf.rb"

foo(Test_Basic.public_instance_methods.grep(/^test_/), "../tests/basic.rb", "Test_Basic", 16)
foo(Test_Big.public_instance_methods.grep(/^test_/), "../tests/big.rb", "Test_Big", 2)
foo(Test_Perf.public_instance_methods.grep(/^test_/), "../tests/perf.rb", "Test_Perf", 3)
