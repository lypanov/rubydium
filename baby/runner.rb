require "basic.rb"

tests = Test_Basic.public_instance_methods.grep(/^test_/)
groups = []
tests.each_slice(16) {
   |slice|
   groups << slice
}

File.open("tmp/test.rb", "wb") {
	|t|
	t.write """
require \"basic.rb\"
class Test_Boo < Test::Unit::TestCase
   include Test_Basic
end
tests = Test_Basic.public_instance_methods.grep(/^test_/)
tests.each {
	|method|
	Test_Basic.module_eval {
	   unless ARGV.include? method
	      undef_method(method)
	   end
	}
}
"""
}

File.open("tmp/Makefile", "wb") {
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
out#{n}: basic.rb
\truby tmp/test.rb #{slice.join " "} > out#{n}
"""
   }
}