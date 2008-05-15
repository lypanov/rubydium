
   def test_2
         do_blah <<SRC, "64\n"
         # highly b0rked
         def recurse n
            if n != 0
               pi n
               recurse(n - 1)
            end
         end
         recurse 1000
SRC
   end

   def test_26
         do_blah <<SRC, "5\n-6\n"
         class Blub
            def two
               pi -6
            end
         end
         class Blah
            def one
               pi 5
               t = Blub.new
               t.two
            end
         end
         Blah.new.one
SRC
   end

   def test_29
         do_blah <<SRC, "5\n6\n6\n5\n6\n6\n"
         # test problematic scoping with multiple proc call's
         block1 = proc { a = 5; pi a }
         a = 6
         block2 = proc { pi a; a = 6; pi a }
         block1.call # 5
         block2.call # 6 6
         block1.call # 5
         block2.call # 6 6
SRC
   end

   def test_33
         do_blah <<SRC, "15\n-5\n"
         # test multiple proc call's
         block1 = proc {
            |p1, p2|
            pi p1 + p2 # -> 5 + 10 == 15
         }
         block2 = proc {
            |p1, p2|
            pi p1 - p2 # -> 5 - 10 == -5
         }
         block1.call 5, 10
         block2.call 5, 10
SRC
   end

   public_instance_methods.each {
      |meth| 
      next if meth !~ /^test.*/ or meth.to_sym == DO_TEST
      remove_method meth.to_sym
   } if defined? DO_TEST

end
