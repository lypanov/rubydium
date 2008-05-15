   def test_math
      t = Context.new
      do_test t, %{
         puts 5 + 6
         puts 5 * 5
         puts 15 % 10
         puts 15 / 10
      }, "11\n25\n5\n1\n"
   end

   def test_typing
      t = Context.new
      do_test t, %{
         a = true
         puts typeof(typeof(a))
         puts typeof(true)
         puts typeof(5)
         puts typeof(typeof(true))
         b = 5
         puts typeof(b)
      }, "3\n1\n2\n3\n2\n"
   end

   def __test_reallocate_byte_array # FIXME
      do_test t, %{
         t = VByteArray.new
         t.realloc 2*4
         t.set_element(0, 10)
         puts t.get_element(0)
         t.set_element(1, 20)
         puts t.get_element(1)
      }, "10\n20\n"
   end

   def test_new_byte_array
      # note - its not yet a byte array its an array of ints so must allocate * 4!
      t = Context.new
      do_test t, %{
         t = VByteArray.new
         t.alloc 2*4
         t.set_element(0, 10)
         puts t.get_element(0)
         t.set_element(1, 20)
         puts t.get_element(1)
      }, "10\n20\n"
      do_test t, %{
         t = VByteArray.new
         t.alloc 2*4
         a = 0
         t.set_element(a, ?h)
         a += 1
         t.set_element(a, ?i)
         a = 0
         putchar t.get_element(a)
         a += 1
         putchar t.get_element(a)
         putchar ?\\n
      }, "hi\n"
   end

   def test_string_constant
      t = Context.new
      do_test t, %{
         t = "this is a string"
         puts typeof(VByteArray.new)
         puts typeof(t) # TODO - for the moment the string is a VByteArray we need to wrap it in RString or so!
         size = t.get_element(0)
         n = 1 # pos 0 is the length
         while n < (size + 1)
            putchar t.get_element(n)
            n += 1
         end
      }, "5\n5\nthis is a string"
   end

   def test_instance_variable
      t = Context.new
      do_test t, %{
         #{$stdlib_member_vars}
         class Blah
            def init
               @a = 800
               @b = 900
            end
            def print_a
               puts @a
               puts @b
            end
         end
         blah = Blah.new
         blah.init
         blah.print_a
      }, "800\n900\n"
   end

   def __test_global_variable # FIXME
      t = Context.new
      do_test t, %{
         class Blah
            def init
               $a = 5
            end
         end
         blah = Blah.new
         blah.init
         puts $a
         $a = 4
         blah.init
         puts $a
      }, "5\n4\n4\n"
   end

   def test_multiple_custom_class_empty_initializer_instance_method_same_method_names
      t = Context.new
      do_test t, %{
         class Test1
            def do_something
               puts 120
            end
         end
         class Test2
            def do_something a
               puts 150 + a
            end
         end
         test1 = Test1.new
         test1.do_something
         test2 = Test2.new
         test2.do_something 5
      }, "120\n155\n"
   end
   
   def test_custom_class_empty_initializer_instance_methods
      t = Context.new
      do_test t, %{
         class Test
            def do_something
               puts 120
            end
            def do_something_2
               puts 150
            end
         end
         test = Test.new
         test.do_something
         test.do_something_2
      }, "120\n150\n"
   end

   def test_stdlib_string
      t = Context.new
      do_test t, %{
       #{$stdlib}
       putstr "blah"
       putstr num_to_s(214)
       # fixme - puts is a builtin that currently just prints an int, should be removed
       puts 214
       puts strlen(concat("foo", "bar"))
       putstr concat("foo", "bar")
      }, "blah214214\n6\nfoobar"
   end

   def __test_method_operator # FIXME
      t = Context.new
      # BROKEN
      do_test t, %{
         t = VByteArray.new
         a = 0
         t[a] = ?a
         puts typeof(t)
      }, "4\n"
   end

   def test_static_methods
      t = Context.new
      do_test t, %{
         class A
            def A.do_it
               putchar ?a
            end
         end
         class B
            def B.do_it
               putchar ?b
            end
         end
         A.do_it
         B.do_it
      }, "ab"
   end

   def test_putchar
      t = Context.new
      do_test t, %{
         dummy = false # another dummy!!! why??? because we don't assign any variables? :|
         putchar ?a
      }, "a"
      do_test t, %{
         n = 15
         last_digit = n % 10
         putchar ?0 + last_digit
      }, "5"
      do_test t, %{
         n = 15
         while n > 0
            ch = ?0 + n % 10
            putchar ch
            n /= 10
         end
      }, "51"
   end

   def test_def
      t = Context.new
      do_test t, %{
         def my_function
            puts 1 != 2
         end
         my_function}, "1\n"
      do_test t, %{
         def my_second_function
            puts 5
         end
         my_second_function}, "5\n"
      do_test t, %{
         def my_other_function2 a
            puts a
         end
         my_other_function2 800}, "800\n"
      do_test t, %{
         def my_other_function3 a, b
            puts a
            puts b + 8
         end
         my_other_function3 700, 800}, "700\n808\n"
      do_test t, %{
         def my_fourth_function a
            puts a
            puts a
         end
         t = 800
         my_fourth_function t}, "800\n800\n"
      do_test t, %{
         def funky
            5
         end
         puts funky}, "5\n"
      do_test t, %{
         def funky2
            return 8
            5
         end
         puts funky2}, "8\n"
   end

   def test_blah
      t = Context.new
      do_test t, %{
         # test out not
         puts 1 != 2
      }, "1\n"
      do_test t, %{
         # test out puts of bools
         dummy = false # FIXME - this is required???
         puts false
         puts true
      }, "0\n1\n"
      do_test t, %{
         # test out equality operators
         puts (1 == 1)
         puts (1 == 2)
      }, "1\n0\n"
      do_test t, %{
         # test out >
         puts (5 > 10)
         puts (5 > 4)
      }, "0\n1\n"
      do_test t, %{
         # test out eq on local vars
         a = 3
         puts a == 3
         puts a == 2
      }, "1\n0\n"
      do_test t, %{
         # while loop
         a = 130
         while a > 120
            puts a
            a += -1
         end
      }, "130\n129\n128\n127\n126\n125\n124\n123\n122\n121\n"
      do_test t, %{
         # if conditional
         a = 100
         if a == 100
            puts 100
         else
            puts -1
         end
         a = 200
         if a == 100
            puts 100
         else
            puts -1
         end
      }, "100\n-1\n"
      do_test t, %{
         # test that a src = dest does a copy of dest
         x = 1
         y = x
         puts x
         puts y
         x += 1
         puts x
         puts y
      }, "1\n1\n2\n1\n"
      do_test t, %{
         # setting/puts of local var
         a = 5
         puts a
      }, "5\n"
      do_test t, %{
         # setting an addition of constant and constant
         y = 6 + 4
         puts y
      }, "10\n"
      do_test t, %{
         # puts of addition of constant and constant
         puts 2 + 2
      }, "4\n"
      do_test t, %{
         # test of localvar += constant construct
         a = 10
         h = 6
         h += 1
         h += a
         puts h
      }, "17\n"
   end

   def test_complex_mult_table
      t = Context.new
      do_test t, %{
         #{$stdlib}
         def mul_line sx, sy, y
            max_num_len = strlen(num_to_s(sx * sy))
            alignment = max_num_len + 1
            x = 1
            while x < (sy + 1)
               num_str = num_to_s(x * y)
               num_spaces = alignment - strlen(num_str)
               c = 0
               while c < num_spaces
                  putstr " "
                  c += 1
               end
               putstr num_str
               x += 1
            end
         end
         def mul_table sx, sy
            y = 1
            while y < (sy + 1)
               mul_line sx, sy, y
               putstr "\\n"
               y += 1
            end
         end
         mul_table 12, 12
      }, "   1   2   3   4   5   6   7   8   9  10  11  12\n   2   4   6   8  10  12  14  16  18  20  22  24\n   3   6   9  12  15  18  21  24  27  30  33  36\n   4   8  12  16  20  24  28  32  36  40  44  48\n   5  10  15  20  25  30  35  40  45  50  55  60\n   6  12  18  24  30  36  42  48  54  60  66  72\n   7  14  21  28  35  42  49  56  63  70  77  84\n   8  16  24  32  40  48  56  64  72  80  88  96\n   9  18  27  36  45  54  63  72  81  90  99 108\n  10  20  30  40  50  60  70  80  90 100 110 120\n  11  22  33  44  55  66  77  88  99 110 121 132\n  12  24  36  48  60  72  84  96 108 120 132 144\n"
   end

   def test_many_nested_function_calls
      t = Context.new
      do_test t, %{
         def blah2 y
            x = 0
            while x < 100
               blah3 x
               x += 1
            end
         end
         def blah3 y
            x = 0
            while x < 100
               x += 1
            end
         end
         blah2 1
      }, ""
   end
