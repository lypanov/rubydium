#include "Mumble.h"

#import "LLVMRubyObjCPlusPlusBridger.h"

@implementation LLVMRubyObjCPlusPlusBridger

- (const char*) foo: (const char*)str {
  return bah2(str);
}


@end

