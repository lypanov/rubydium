   def test_35
         do_blah <<SRC, "15\n"
         # test simple proc.call
         my_block = proc {
            |p1|
            pi p1
         }
         my_block.call 5
SRC
   end
      
   def test_17
         do_blah <<SRC, "200\n"
         class Book
            def self.blah a,b
               a*b*10
            end
         end
         pi Book.blah 4,5
SRC
   end

   def test_34_two_param_block_arg
         do_blah <<SRC, "20\n"
         # test passing block as argument
         def blah num, &block
            block.call num, num + 10
         end
         blah(5) {
            |p1, p2|
            pi p1 + p2
         }
SRC
   end

   def test_32
      return
         do_blah <<SRC, /error: attempting to access unused local 'a' from \d+$\n/, [362, 592]
         # test scoping - calling a method should push a new lexical pad and thusly in this case, fail
         def inner_scope
            a += 5
         end
         a = 5
         inner_scope
         pi a
SRC
   end

   def test_perf_iterator_semi_complex
      return
   do_blah <<SRC, "13\n13\n13\n13\n13\n13\n13\n13\n13\n13\n"
         class Blah
            def test3
               10
            end
            def test2 a, b
               t = a + b + test3
               t
            end
         end
         def times n
            ln = 0
            while ln < n
               ln += 1
               yield
            end
         end
         blah = Blah.new
         times(#{real_test? ? 50 : 4}) {
            pi blah.test2(1, 2)
         }
SRC
   end

   def test_48
      do_blah <<SRC, "5\n0\n1\n", [108, 111]
         # test == operator
         pi 5
         pi 5 == 6 # should be false not 0!
         pi 5 == 5
SRC
   end

   def test_47
      do_blah <<SRC, nil, [201, 226]
         # test typeof - for integer and bool only
         # "3\\n5\\n2\\n0\\n3\\n5\\n2\\n1\\n"
         test_integer = 5
         test_bool = false
         pi typeof(test_integer)
         pi test_integer
         pi typeof(test_bool)
         pi test_bool
         pi typeof(5)
         pi 5
         pi typeof(true)
         pi true
SRC
   end
   
   def test_17_instance_methods_and_typeof
         do_blah <<SRC, nil, [615, 1183]
         class Blah
            def test1
               pi 5
            end
            def test2
               pi 6
            end
         end
         blah = Blah.new
         blah.test1
         blah.test2
         pi typeof(blah)
SRC
   end
   
   def test_25
      return
         do_blah <<SRC, nil, [27786, 15237]
         class Blah
            def init
               alloc_self
               set 0, 0
            end
            def print
               len = get 0
               pos = 0
               while true
                  pos += 1
                  putch get(pos)
                  if pos == len
                     break 
                  end
               end
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
         def print_num int, just
            num = Blah.new
            num.init
            num.from_int int
            ln = 0
            while ln < (just - num.length)
               ln += 1
               putch ?\\s
            end
            num.print
         end
         def print_line m, just, num_columns
            n = 1
            ln = 0
            while ln < num_columns
               print_num n * m, just
               n += 1
               ln += 1
            end
            putch ?\\n
         end
         def doop
            num_columns = 3
            num_rows    = 3
            max = Blah.new
            max.init
            max.from_int(num_columns * num_rows)
            just = 1 + max.length
            n = 1
            ln = 0
            while ln < num_rows
               ln += 1
               print_line n, just, num_columns
               n += 1
            end
         end
         doop
SRC
   end

   