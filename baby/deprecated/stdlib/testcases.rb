require "test/unit"
$:.unshift File.dirname((File.readlink($0) rescue $0))
require "machine.rb"
require "string.rb"

def run_and_collect_exception
   exception = nil
   begin
      yield
   rescue => e
      exception = e
   end
   exception 
end

class TC_TestMachine < Test::Unit::TestCase
   def test_set base, val
      needed_rescue = nil
      begin 
         needed_rescue = false
         base.data = val
      rescue => e
         needed_rescue = true
      end
      needed_rescue ? nil : base.data
   end
   def do_test_number base, bits
      assert_equal nil, test_set(base, -1)
      assert_equal 0,   test_set(base, 0)
      assert_equal 2**bits- 1, test_set(base, 2**bits - 1)
      assert_equal nil, test_set(base, 2**bits)
      assert_equal nil, test_set(base, 2**(bits + 1))
   end
   def test_byte
      do_test_number VByte.new, 8
   end
   def test_short
      do_test_number VShort.new, 16
   end
   def test_int
      do_test_number VInt.new, 32
   end
   def fill_and_compare ba, size
      (0...size).each {
         |idx|
         ba.byte_at_index(idx).data = idx
      }
      array = (0...size).collect { |idx| ba.byte_at_index(idx).data }
      assert_equal (0...size).to_a, array
   end
   def test_bytearray
      ba = VByteArray.new 32
      fill_and_compare ba, 32
   end
   def test_bytearray_resize
      ba = VByteArray.new 32
      fill_and_compare ba, 32
      ba.expand 64
      fill_and_compare ba, 64
      ba.trunc 16
      assert_equal nil, run_and_collect_exception { fill_and_compare ba, 16 }
      assert_not_equal nil, run_and_collect_exception { fill_and_compare ba, 64 }
      ba.trunc 8
      assert_not_equal nil, run_and_collect_exception { fill_and_compare ba, 9 }
   end
end

class TC_TestStdLib < Test::Unit::TestCase
   def test_rstring
      rstr = RString.new
      assert_equal 0, rstr.length
      rstr.prealloc 1 
      assert_equal VByte, rstr[0].class
      rstr[0].data = ?a
      assert_equal ?a, rstr[0].data
   end
   def rstring_from_string str
      rstr = RString.new
      rstr.prealloc str.length
      idx = 0
      str.each_byte { |b| rstr[idx].data = b; idx += 1 }
      rstr
   end
   def rstring_to_string rstr
      str = String.new
      rstr.each_byte { |b| str << b.data }
      str
   end
   def test_rstring_slice
      assert_equal 5, rstring_from_string("abcde").length
      assert_equal ?a, rstring_from_string("abcde")[0].data
      assert_equal ?c, rstring_from_string("abcde")[2].data
      assert_equal "abcde", rstring_to_string(rstring_from_string("abcde"))
      assert_equal nil, rstring_from_string("abcde")[5]
      assert_equal 0, rstring_from_string("").length
      assert_equal "bcd", rstring_to_string(rstring_from_string("abcde")[1..3])
      assert_equal "abcde", rstring_to_string(rstring_from_string("abcde")[0..4])
   end
end

require "test/unit/ui/console/testrunner"
Test::Unit::UI::Console::TestRunner.run(TC_TestMachine)
Test::Unit::UI::Console::TestRunner.run(TC_TestStdLib)
