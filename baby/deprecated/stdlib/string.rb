require "machine.rb"

class RString
   def initialize
      @bytearray = VByteArray.new 0
      @len = 0
   end
   def [] idx
      # convert to use RArray and RObject
      case idx
      when Integer # -> RInt
         idx >= @len ? nil : @bytearray.byte_at_index(idx)
      when Range # -> RRange
         rng = idx
         rstr = RString.new
         len = rng.max - rng.min + 1
         rstr.prealloc len
         it = 0
         while true
            val = self[idx.min + it].data
            rstr[it].data = val
            it += 1
            break if it >= len
         end
         return rstr
      end
   end
   def prealloc len
      @bytearray.expand len
      @len = len
   end
   def + a, b
      str = RString.new
      str.prealloc a.length + b.length
      p = 0
      a.each_byte { |byte| str[p].data = byte; p += 1 }
      b.each_byte { |byte| str[a.length + p].data = byte; p += 1 }
   end
   def each_byte
      idx = 0
      while true
         yield self[idx]
         idx += 1
         break if idx == @len
      end
   end
   def length
      @len
   end
end
