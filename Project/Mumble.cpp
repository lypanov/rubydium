#define __STDC_LIMIT_MACROS

#include "Mumble.h"

#include "llvm/Module.h"
#include "llvm/ModuleProvider.h"
#include "llvm/Type.h"
#include "llvm/Assembly/Parser.h"
#include "llvm/Bitcode/ReaderWriter.h"
#include "llvm/CodeGen/LinkAllCodegenComponents.h"
#include "llvm/ExecutionEngine/JIT.h"
#include "llvm/ExecutionEngine/GenericValue.h"
#include "llvm/Support/ManagedStatic.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/System/Process.h"
#include <fstream>
#include <iostream>

using namespace llvm;

std::auto_ptr<Module> foobar(const char *boo) {
  ParseError Err;
  std::auto_ptr<Module> M(ParseAssemblyString(boo, 0, &Err));
  if (M.get() == 0) {
    cerr << ": " << Err.getMessage() << "\n"; 
  }
  return M;
}


/*

  std::ostream *Out = new std::ofstream("/Users/lypanov/llvmrb/foo.lli.bc", std::ios::out |  
                          std::ios::trunc | std::ios::binary);
  if (!Out->good()) {
    cerr << ": error opening " << "!\n";
    return 0;
  }
  WriteBitcodeToFile(M.get(), *Out);

  std::string ErrorMsg;
  ModuleProvider *MP = 0;
  if (MemoryBuffer *Buffer = MemoryBuffer::getFileOrSTDIN("/Users/lypanov/llvmrb/foo.lli.bc", &ErrorMsg)) {
    MP = getBitcodeModuleProvider(Buffer, &ErrorMsg);
    if (!MP) {
		delete Buffer;
	}
  }
  

*/
const char* bah2(const char *boo) {
  static ExecutionEngine *EE = 0;

  std::auto_ptr<Module> M = foobar(boo);

  if (!EE) {
	EE = ExecutionEngine::create(M.get());
  }
  
  Function *Fn = M->getFunction("foo");
  if (!Fn) {
    std::cerr << "'foo' function not found in module.\n";
  }

  std::vector<GenericValue> args(1);
  args[0].IntVal = APInt(64, 5);

  GenericValue Result = EE->runFunction(Fn, args);
  return Result.IntVal.toString(10, false).c_str();
}