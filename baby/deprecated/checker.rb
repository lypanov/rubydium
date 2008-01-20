require 'ruby/parse'
include Ruby
class AstCrawler
   attr_accessor :ast, :id2path_hash
   def initialize ast
      @ast = ast
      @id2path_hash = {}
      preload_ast ast, []
      @id2path_hash[@id2path_hash.length] = []
   end
   def self.find_subpaths path_list, subpath_root
      return path_list.find_all {
         |path|
         prefix = path.slice 0, subpath_root.length
         (path.length > subpath_root.length) \
     and (prefix === subpath_root)
   }
   end
   def preload_ast ast, path
      order_arr = ast.to_a.inject([]) { |oarr, elt| oarr << [elt, oarr.size]; oarr }
      order_arr << order_arr.slice!(0) if (ast.is_a? Call)
      order_arr.each {
         |(inner_ast, idx)|
         new_path = path + [idx]
         if inner_ast.class.to_s =~ /(Ruby::AST|Array)/
            preload_ast inner_ast, new_path
         end
         @id2path_hash[@id2path_hash.length] = new_path
      }
   end
   def path2id path
      @id2path_hash.index path
   end
   def id2path id
      @id2path_hash[id]
   end
   def find_path to_find, ast = nil, path = nil
      ast  = @ast if ast.nil?
      path = []   if path.nil?
      return ast  if to_find.empty?
      ast.to_a.each_with_index {
         |inner_ast, idx|
         # if the current element of to_find == the current idx
         if idx == to_find[path.length]
            if (path.length + 1) == to_find.length
                return inner_ast
            else
                return find_path to_find, inner_ast, path + [idx]
            end
         end
      }
      raise "eek! we couldn't find the index!!"
   end
end
def gb statement
   p statement.methods - Object.instance_methods - Enumerable.instance_methods
end
src = <<RB
class Boo
   def t
      @blah = 5
      puts @blah
      puts @bah
   end
end
class Blub
   def t
      puts @blah
      @bah = 5
   end
end
class Blooper < Blub
   def t
      @bah = 7
      p @bah
   end
end
RB
ast = Ruby.parse src
@crawler = AstCrawler.new ast
ast_order = @crawler.id2path_hash.keys.sort.collect { 
   |id|
   path = @crawler.id2path_hash[id]
   ast_subtree = @crawler.find_path(path)
   actual_ast = (ast_subtree.class.to_s.index("Ruby::AST") == 0)
   next unless actual_ast
   next if ast_subtree.is_a? AST::ArrayLiteral # when we use array's in the code, this will have to change...
   next if ast_subtree.is_a? AST::Block
   path
}.compact
classes, super_classes, done_paths = {}, {}, []
while true
   anon_block_path = ast_order.detect { |path| @crawler.find_path(path).is_a? AST::Klass \
                                            and !done_paths.include? path }
   break if anon_block_path.nil?
   done_paths << anon_block_path
   klass_name = @crawler.find_path(anon_block_path).name.constant
   super_class = @crawler.find_path(anon_block_path).superclass.value rescue nil
   if !super_class.nil?
      super_classes[klass_name] = super_class
   end
   subpaths = AstCrawler.find_subpaths(ast_order, anon_block_path) + [anon_block_path]
   subpaths.each { |path| ast_order.delete path }
   classes[klass_name] = subpaths
end
known_ivars = classes.keys.inject({}) { |h,c| h[c] = []; h }
classes.each_pair {
   |klass_name, class_ast_order|
   class_ast_order.each {
      |path|
      node = @crawler.find_path(path)
      case node
      when Iasgn
         known_ivars[klass_name] << node.attr_name
      end
   }
}
known_ivars.each {
   |klass_name, ivars|
   if super_classes.has_key? klass_name and 
      super_ivars = known_ivars[super_classes[klass_name]]
      ivars.each {
         |ivar|
         puts "overriden attribute definition: #{ivar} in #{klass_name} overrides same attribute in #{super_classes[klass_name]}" \
            if super_ivars.include? ivar
      }
   end
}
classes.each_pair {
   |klass_name, class_ast_order|
   class_ast_order.each {
      |path|
      node = @crawler.find_path(path)
      case node
      when Ivar
         puts "unknown attribute #{node.attr_name} in #{klass_name}" \
          unless known_ivars[klass_name].include? node.attr_name
      end
   }
}
