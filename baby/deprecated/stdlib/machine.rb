class VNumberBase
   def initialize limit_range
      @data = 0
      @limit = limit_range
   end
   def data= new_value
      if @limit === new_value
         @data = new_value
      else
         raise "out of range..."
      end
   end
   def data
      @data
   end
end

class VByte < VNumberBase
   def initialize
      super(0...2**8)
   end
end

class VShort < VNumberBase
   def initialize
      super(0...2**16)
   end
end

class VInt < VNumberBase
   def initialize
      super(0...2**32)
   end
end

class VByteArray
   def initialize len
      @len = len
      @data = []
      len.times { @data << VByte.new } 
   end
   def byte_at_index idx
      raise "out of array" if idx >= @data.length
      @data[idx]
   end
   def expand len
      len.times { @data << VByte.new } 
   end
   def trunc len
      @data.slice!(len..-1)
   end
end
