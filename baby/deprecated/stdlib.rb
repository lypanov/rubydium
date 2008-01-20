   def strlen str
      return str.get_element(0)
   end
   def putstr str
      size = str.get_element(0)
      n = 1 # pos 0 is the length
      while n < (size + 1)
         putchar str.get_element(n)
         n += 1
      end
   end
   def num_to_s num
      n = num
      pos = 0
      while n > 0
         pos += 1
         n /= 10
      end
      t = VByteArray.new
      t.alloc((pos + 1) * 4)
      size = pos
      t.set_element(0, size)
      n = num
      while n > 0
         ch = ?0 + n % 10
         t.set_element(pos, ch)
         n /= 10
         pos += -1
      end
      t
   end
   def concat str1, str2
      str1_len = str1.get_element(0)
      str2_len = str2.get_element(0)
      sum = str1_len + str2_len 
      t = VByteArray.new
      t.alloc((sum + 1) * 4)
      t.set_element(0, sum)
      pos = 1
      n = 0
      while n < str1_len
         ch = str1.get_element(n + 1)
         t.set_element(pos, ch)
         n += 1
         pos += 1
      end
      n = 0
      while n < str2_len
         ch = str2.get_element(n + 1)
         t.set_element(pos, ch)
         n += 1
         pos += 1
      end
      t
   end
