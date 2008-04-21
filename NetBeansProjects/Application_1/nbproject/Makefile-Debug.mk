#
# Gererated Makefile - do not edit!
#
# Edit the Makefile in the project folder instead (../Makefile). Each target
# has a -pre and a -post target defined where you can add customized code.
#
# This makefile implements configuration specific macros and targets.


# Environment
MKDIR=mkdir
CP=cp
CCADMIN=CCadmin
RANLIB=ranlib
CC=gcc
CCC=g++
CXX=g++
FC=

# Include project Makefile
include Makefile

# Object Directory
OBJECTDIR=build/Debug/GNU-MacOSX

# Object Files
OBJECTFILES= \
	${OBJECTDIR}/newmain.o

# C Compiler Flags
CFLAGS=

# CC Compiler Flags
CCFLAGS=-D__STDC_LIMIT_MACROS
CXXFLAGS=-D__STDC_LIMIT_MACROS

# Fortran Compiler Flags
FFLAGS=

# Link Libraries and Options
LDLIBSOPTIONS=-L/Users/lypanov/install/llvm/lib

# Build Targets
.build-conf: ${BUILD_SUBPROJECTS} dist/Debug/GNU-MacOSX/application_1

dist/Debug/GNU-MacOSX/application_1: ${OBJECTFILES}
	${MKDIR} -p dist/Debug/GNU-MacOSX
	${LINK.cc} /Users/lypanov/install/llvm/lib/LLVMSparc.o /Users/lypanov/install/llvm/lib/LLVMPowerPC.o /Users/lypanov/install/llvm/lib/LLVMMSIL.o /Users/lypanov/install/llvm/lib/LLVMMips.o -lLLVMLinker -lLLVMipo /Users/lypanov/install/llvm/lib/LLVMInterpreter.o -lLLVMInstrumentation /Users/lypanov/install/llvm/lib/LLVMIA64.o /Users/lypanov/install/llvm/lib/LLVMExecutionEngine.o /Users/lypanov/install/llvm/lib/LLVMJIT.o -lLLVMDebugger /Users/lypanov/install/llvm/lib/LLVMCellSPU.o /Users/lypanov/install/llvm/lib/LLVMCBackend.o -lLLVMBitWriter /Users/lypanov/install/llvm/lib/LLVMX86.o -lLLVMAsmParser /Users/lypanov/install/llvm/lib/LLVMARM.o -lLLVMArchive -lLLVMBitReader /Users/lypanov/install/llvm/lib/LLVMAlpha.o -lLLVMSelectionDAG -lLLVMCodeGen -lLLVMScalarOpts -lLLVMTransformUtils -lLLVMipa -lLLVMAnalysis -lLLVMTarget -lLLVMCore -lLLVMSupport -lLLVMSystem -o dist/Debug/GNU-MacOSX/application_1 ${OBJECTFILES} ${LDLIBSOPTIONS} 

${OBJECTDIR}/newmain.o: newmain.cpp 
	${MKDIR} -p ${OBJECTDIR}
	$(COMPILE.cc) -g -I/Users/lypanov/install/llvm/include -o ${OBJECTDIR}/newmain.o newmain.cpp

# Subprojects
.build-subprojects:

# Clean Targets
.clean-conf:
	${RM} -r build/Debug
	${RM} dist/Debug/GNU-MacOSX/application_1

# Subprojects
.clean-subprojects:
