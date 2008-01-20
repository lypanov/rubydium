# TODO - in the machine impl itself currently initialize is not called automatically
class Object
   def alloc_self
      @data = []
   end
   def set a, b
      @data[a] = b
   end
   def get a
      @data[a]
   end
   def set_self string
      @data = [string.length]
      string.each_byte { |b| @data << b }
   end
end
module Kernel
   def pi integer
      puts integer.to_s
   end
   def putch byte
      Kernel.print byte.chr
   end
end
String = Class.new
         class String
            def initialize
               alloc_self
               set 0, 0
            end
            def alloc size
               set 0, size
            end
            def setdata ba
               set_self ba
            end
            def []= a, b
               set a, b
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
         class Integer
            undef_method :times
            def times
               ln = 0
               while ln < self
                  ln += 1
                  yield
               end
            end
         end
         class Fixnum # BigNum too i guess?
            undef_method :to_s
            def to_s
               n = self
               pos = 0
               while n > 0
                  pos += 1
                  n /= 10
               end
               str = String.new
               size = pos
               str.alloc size
               n = self
               while n > 0
                  ch = ?0 + n % 10
                  str[pos] = ch
                  n /= 10
                  pos += -1
               end
               str
            end
         end
         def print_num int, just
            num = int.to_s
            (just - num.length).times {
               putch ?\s
            }
            num.print
         end
         def print_line m, just, num_columns
            n = 1
            num_columns.times {
               print_num n * m, just
               n += 1
            }
            putch ?\n
         end
         num_columns = 12
         num_rows    = 12
         max = (num_columns * num_rows).to_s
         just = 1 + max.length
         n = 1
         num_rows.times {
            print_line n, just, num_columns
            n += 1
         }
