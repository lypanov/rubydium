#!/usr/bin/env ruby

require "testing.rb"

module Test_Perf

   include TestMod

   # DO_TESTS = [:test_perf_inc_while_with_break]

   def real_test?
      (!Comparison.left? and !Comparison.right?)
   end

   def test_perf_inc_while_with_break
         do_blah <<SRC, nil, [65131, 439]
         n = 0
         while true
            n += 1
            if n == 1000
               break
            end
         end
         pi n
SRC
   end

   def test_perf_instantiate_call_instance_method
         do_blah <<SRC, nil, [9993, 848]
         class Blah
            def one
               1
            end
         end
         n = 0
         while n < 50
            t = Blah.new
            n += t.one
         end
         pi n
SRC
   end

   def test_perf_call_two_methods
         do_blah <<SRC, nil, [6169, 866]
         def bub
            1
         end
         def bub2
            1
         end
         a = 0
         while a < 50
            a += bub
            a += bub2
            pi a
         end
         pi a
SRC
   end

   def test_perf_call_single_method
      # TODO - this is broken when we use 2000 instead of 1000...
      count = real_test? ? 1000 : 20
         do_blah <<SRC, nil, [129206, 597]
         def bub
            1
         end
         a = 0
         while a < #{count}
            # breakpoint
            a += bub
         end
         pi a
SRC
   end

   def test_perf_trivial_while
         do_blah <<SRC, nil, [9361, 344]
         a = 0
         while a < 200
            a += 1
            pi 1
         end
         pi a
SRC
   end

   def test_perf_iterator
         do_blah <<SRC, nil, [4635, 2649]
         def times n
            ln = 0
            while ln < n
               ln += 1
               yield
            end
         end
         class Blah
            def test a
               a = a * 2
               a += 1
               pi a
            end
         end
         c = 1
         times(10) {
            b = Blah.new
            b.test c
         }
SRC
   end

   public_instance_methods.each {
      |meth| 
      next if meth !~ /^test.*/ or DO_TESTS.include? meth.to_sym
      remove_method meth.to_sym
   } if defined? DO_TESTS
end
