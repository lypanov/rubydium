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
OBJECTDIR=build/Release/GNU-MacOSX

# Object Files
OBJECTFILES= \
	${OBJECTDIR}/newmain.o

# C Compiler Flags
CFLAGS=

# CC Compiler Flags
CCFLAGS=
CXXFLAGS=

# Fortran Compiler Flags
FFLAGS=

# Link Libraries and Options
LDLIBSOPTIONS=

# Build Targets
.build-conf: ${BUILD_SUBPROJECTS} dist/Release/GNU-MacOSX/application_1

dist/Release/GNU-MacOSX/application_1: ${OBJECTFILES}
	${MKDIR} -p dist/Release/GNU-MacOSX
	${LINK.cc} -o dist/Release/GNU-MacOSX/application_1 ${OBJECTFILES} ${LDLIBSOPTIONS} 

${OBJECTDIR}/newmain.o: newmain.cpp 
	${MKDIR} -p ${OBJECTDIR}
	$(COMPILE.cc) -O2 -o ${OBJECTDIR}/newmain.o newmain.cpp

# Subprojects
.build-subprojects:

# Clean Targets
.clean-conf:
	${RM} -r build/Release
	${RM} dist/Release/GNU-MacOSX/application_1

# Subprojects
.clean-subprojects:
