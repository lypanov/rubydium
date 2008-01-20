class String
   def indent n
      ind = " " * n
      lines = self.split "\n"
      lines.map { |line| ind + line }.join "\n"
   end
end

def gb statement
   p statement.methods - Object.instance_methods - Enumerable.instance_methods
end

