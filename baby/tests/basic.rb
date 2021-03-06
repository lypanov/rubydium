#!/usr/bin/env ruby

require "testing.rb"

module Test_Basic

   include TestMod
   
   # DO_TESTS = [:test_46]
   def test_46
         do_blah <<SRC, "2\n2\n", [178, 477]
         # test top level if, requires handling of :if in handle_element, other pathways don't hit that for some reason?
         n = 2
         if n == 1
            pi 1
         end
         if n == 2
            pi 2
         end
         pi n
SRC
   end
   
   def test_44_trivial_block_arg
         do_blah <<SRC, "5\n1\n5\n2\n", [794, 1428]
         # test trivial block - no complex scopes
         def blah &block
            block.call 1
            block.call 2
         end
         a = 5
         blah {
            |val|
            pi a
            pi val
         }
SRC
   end

   def test_31_scoping
         do_blah <<SRC, "-5\n2\n5\n-5\n2\n5\n", [535, 802]
         # test scoping - calling a method should push a new lexical pad
         def inner_scope
            a = 2
            pi -5
            pi a
         end
         a = 5
         inner_scope # -5, 2
         pi a        # 5
         inner_scope # -5, 2
         pi a        # 5
SRC
   end
   
   def test_8_instance_method_calls_self_method
         do_blah <<SRC, "2\n", [635, 902]
         class Boo
            def two
               one + one
            end
            def one
               1
            end
         end
         t = Boo.new
         pi t.two
SRC
   end
   
   def test_12_instance_variable_hooks
         do_blah <<SRC, "25\n100\n", [1746, 3120]
         class Blah
            def init
               alloc_self
            end
            def callhookload a
               dget a
            end
            def callhook b, a
               dset a, b
            end
            def test_self
               @a = 25
               @b = 100
               pi @a
               pi @b
            end
         end
         blah = Blah.new
         blah.init
         blah.test_self
SRC
   end

   def test_empty_class_def
         do_blah <<SRC, "2\n", [85, 88]
         class Blah
            # class can't be empty!
         end
         pi 2
SRC
   end

   def test_1_templates_scopes
      do_blah <<SRC, nil, [1654, 2041]
         # useful for testing templated scopes
         def scope1 a, b
            b = -2
            c = -3
            pi a
            pi b
            pi c
         end
         def do_it t
            scope1 t, t + 1
         end
         do_it 1
         do_it 2
         do_it 3
         do_it 4
SRC
   end

   def test_2_simple_yield_instance_method
         do_blah <<SRC, nil, [1137, 2160]
         class Test
            def init
               alloc_self
            end
            def looper
               yield 1
               yield 2
               yield 3
            end
            def looping num
               looper {
                  |n|
                  pi n
               }
            end
         end
         t = Test.new
         t.looping 3
SRC
   end

   def test_3_trivial_yield
         do_blah <<SRC, nil, [1486, 3667]
      def blah
         yield 1
         yield 2
         yield 3
         yield 4
         yield 5
         yield 6
         pi -1
      end
      blah {
         |n|
         pi n
      }
      pi -1
SRC
   end

   def test_4_while_break_yield
         do_blah <<SRC, nil, [1637, 2487]
      def count_up_to top
         n = 0
         while true
            n += 1
            yield n
            break if n == top
         end
      end
      def do_this h
         count_up_to(h) {
            |h|
            pi h
         }
      end
      do_this 2
      do_this 2
SRC
   end

   def test_5_simple_yield
         do_blah <<SRC, nil, [1098, 2687]
         def thrice
            yield
            yield
            yield
            yield
            yield
         end
         n = 0
         thrice {
            n += 1
            pi n
         }
         pi -1
         pi n
SRC
   end

   def test_6_most_basic_yield
         do_blah <<SRC, nil, [493, 1099]
         def thrice
            pi 1
            yield
            pi 3
            yield
         end
         thrice {
            pi 1
         }
SRC
   end

   def test_7_method_calling_method
         do_blah <<SRC, nil, [384, 574]
         def seven
            pi 7
         end
         def six
            seven
         end
         def five
            six
         end
         five
SRC
   end

   def test_9_looped_instance_create_and_method_call
         do_blah <<SRC, nil, [1033, 903]
         class Blah
            def five
               5
            end
         end
         n = 0
         while true
            t = Blah.new
            pi t.five
            n += 1
            break if n > 3
         end
SRC
   end

   def test_10_trivial_math
         do_blah <<SRC, nil, [114, 136]
         t = 5 * 6
         pi t + 2
SRC
   end

   def test_11_return_from_instance_method
         do_blah <<SRC, nil, [525, 1036]
         # testcase for return values on instance methods
         # problem was caused as fall through to Def at end of 
         # method happened and the return value was discarded
         class Blah
            def test2 a, b
               t = a + b
               10 + t
            end
         end
         blah = Blah.new
         pi blah.test2(5, 6)
SRC
   end

   def test_13_dict_get_set
         do_blah <<SRC, nil, [626, 1040]
         class Blah
            def init
               alloc_self
               dset ?a, 10
               dset ?b, 20
            end
            def test
               pi (dget ?a)
               pi (dget ?b)
            end
         end
         blah = Blah.new
         blah.init
         blah.test
SRC
   end

   def test_14_instance_method_calls_kernel_method
         do_blah <<SRC, nil, [541, 795]
         class Boo
            def calc
               pi 5
               doodle
            end
         end
         # main
         def doodle
            pi 6
         end
         boo = Boo.new
         boo.calc
         doodle
SRC
   end

   def test_15_trivial_while_break
         do_blah <<SRC, nil, [248, 420]
         n = 0
         while true
            pi n
            n += 1
            break if n == 2
         end
SRC
   end

   def test_16_set_get
         do_blah <<SRC, nil, [744, 1161]
         class Blah
            def one
               alloc_self
               set 1, 50
               pi 5
               two
            end
            def two
               pi get(1)
               pi get(1)
               three
            end
            def three
               pi 30 - 5
            end
         end
         blah = Blah.new
         blah.one
SRC
   end
   
   def test_18_trivial_yield_simple_scope
         do_blah <<SRC, nil, [592, 1213]
         # test trivial yield - no complex scopes
         def blah
            yield 1
            yield 2
         end
         blah {
            |val|
            pi val
         }
SRC
   end

   def test_36
         do_blah <<SRC, nil, [1130, 2045]
         # test yielding while loop with a break
         def blah
            n = 0
            while n < 5
               yield n
               n += 1
               break if n == 3
            end
            pi 8
         end
         blah {
            |val|
            pi val
         }
         pi 9
SRC
   end

   def test_37
         do_blah <<SRC, nil, [375, 545]
         # test while loop with a break
         n = 0
         while n < 5
            pi n
            n += 1
            break if n == 3
         end
         pi 9
SRC
   end

   def test_38
         do_blah <<SRC, nil, [897, 1300]
         # test iterators in global methods
         def times n
            ln = 0
            while ln < n
               ln += 1
               yield
            end
         end
         def test
            times(3) {
               pi 5
            }
         end
         test
SRC
   end

   def test_39
         do_blah <<SRC, nil, [847, 1386]
         # test an implementation of times method
         def times n
            ln = 0
            while ln < n
               ln += 1
               yield
            end
         end
         times(3) {
            pi 5
         }
SRC
   end

   def test_40
         do_blah <<SRC, nil, [1564, 2109]
         # test yielding while loop - while end condition is tested in this one, but not in the above one
         def blah
            n = 0
            while n < 5
               yield n
               n += 1
            end
            pi 8
         end
         blah {
            |val|
            pi val
         }
         pi 9
SRC
   end

   def test_41
         do_blah <<SRC, nil, [509, 797]
         # test multiple method definitions with differing prototypes
         def blah
            pi 8
         end
         def blah2 n
            pi 9 + n
         end
         blah
         blah2 10
         blah
SRC
   end

   def test_43
         do_blah <<SRC, nil, [705, 1479]
         # test trivial yield
         def blah
            yield 1
            yield 2
         end
         idx = 5
         blah {
            |val|
            idx = val
         }
         pi idx
SRC
   end

   def test_45
         do_blah <<SRC, nil, [435, 467]
         # test while loop
         n = 0
         while n < 5
            pi n
            n += 1
         end
         pi n
SRC
   end

   public_instance_methods.each {
      |meth| 
      next if meth !~ /^test.*/ or DO_TESTS.include? meth.to_sym
      remove_method meth.to_sym
   } if defined? DO_TESTS
end
