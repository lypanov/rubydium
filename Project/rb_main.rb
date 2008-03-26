framework 'Cocoa'
bridge = LLVMRubyObjCPlusPlusBridger.new
# fail "um1" unless (bridge.foo('define i64 @foo(i64 %bah) { ret i64 10 }') == "10")
fail "um2" unless (bridge.foo('define i64 @foo(i64 %bah) { ret i64 %bah }') == "5")
