#!/usr/bin/env ruby

require "testing.rb"

class Test_Big < Test::Unit::TestCase

   include TestMod

   # DO_TESTS = [:test_25_yields]

   def test_24
         do_blah <<SRC, nil, [14392, 6507]
         class Blah
            def init
               alloc_self
               set 0, 0
            end
            def setdata ba
               set_self ba
            end
            def letters
               len = get 0
               pos = 0
               while true
                  pos += 1
                  yield get(pos)
                  if pos == len
                     break 
                  end
               end
            end
            def print
               letters {
                  |char|
                  putch char
               }
               pi -5
            end
         end
         def times n
            ln = 0
            while ln < n
               ln += 1
               yield
            end
            pi -5
         end
         str = Blah.new
         str.init
         str.setdata "hello world\n"
         times(3) {
            str.print
         }
SRC
   end

   def test_25_yields
         do_blah <<SRC, nil, [32298, 16183]
         class Blah
            def init
               alloc_self
               set 0, 0
            end
            def setdata ba
               set_self ba
            end
            def letters
               len = get 0
               pos = 0
               while true
                  pos += 1
                  yield get(pos)
                  if pos == len
                     break 
                  end
               end
            end
            def addchar ch
               set 0, (get 0) + 1
               set (get 0), ch
            end
            def print
               letters {
                  |char|
                  putch char
               }
            end
            def from_int num
               n = num
               pos = 0
               while n > 0
                  pos += 1
                  n /= 10
               end
               # alloc size (pos + 1) * 4
               size = pos
               set 0, size
               n = num
               while n > 0
                  ch = ?0 + n % 10
                  set pos, ch
                  n /= 10
                  pos += -1
               end
            end
            def concat str
               str.letters {
                  |ch|
                  addchar ch
               }
            end
            def length
               get 0
            end
         end
         def times n
            ln = 0
            while ln < n
               ln += 1
               yield
            end
         end
         def print_num int, just
            num = Blah.new
            num.init
            num.from_int int
            times(just - num.length) {
               putch ?\\s
            }
            num.print
         end
         def print_line m, just, num_columns
            n = 1
            times(num_columns) {
               print_num n * m, just
               n += 1
            }
            putch ?\\n
         end
         num_columns = 3
         num_rows    = 3
         max = Blah.new
         max.init
         max.from_int(num_columns * num_rows)
         just = 1 + max.length
         n = 1
         times(num_rows) {
            print_line n, just, num_columns
            n += 1
         }
SRC
   end

   def test_49 
      n = ARGV.length > 0 ? ARGV.first.to_i : 3
      str_impl = (<<EOF)
         class Blah
            def init
               alloc_self
               set 0, 0
            end
            def letters
               len = get 0
               pos = 0
               while true
                  pos += 1
                  yield get(pos)
                  if pos == len
                     break 
                  end
               end
            end
            def print
               letters {
                  |char|
                  putch char
               }
            end
            def from_int num
               n = num
               pos = 0
               while n > 0
                  pos += 1
                  n /= 10
               end
               # alloc size (pos + 1) * 4
               size = pos
               set 0, size
               n = num
               while n > 0
                  ch = ?0 + n % 10
                  set pos, ch
                  n /= 10
                  pos += -1
               end
            end
            def length
               get 0
            end
         end
         def from_and_to l, h
            ln = l
            while ln < h
               ln += 1
               yield ln
            end
         end
EOF
         do_blah <<SRC, nil, [34854, 14403]
         #{str_impl}
      def print_spaces n
         from_and_to(1, n) {
            |n|
            putch ?\\s
         }
      end
      def boo t
         from_and_to(0, #{n}) {
            |n|
            num = Blah.new
            num.init
            num.from_int n * t
            print_spaces 5 - num.length
            num.print
         }
         putch ?\\n
      end
         from_and_to(0, #{n}) {
            |n|
            boo n
         }
SRC
   end

   public_instance_methods.each {
      |meth| 
      next if meth !~ /^test.*/ or DO_TESTS.include? meth.to_sym
      remove_method meth.to_sym
   } if defined? DO_TESTS
end
