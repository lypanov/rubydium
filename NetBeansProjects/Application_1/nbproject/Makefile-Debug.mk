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
CCFLAGS=
CXXFLAGS=

# Fortran Compiler Flags
FFLAGS=

# Link Libraries and Options
LDLIBSOPTIONS=

# Build Targets
.build-conf: ${BUILD_SUBPROJECTS} dist/Debug/GNU-MacOSX/application_1

dist/Debug/GNU-MacOSX/application_1: ${OBJECTFILES}
	${MKDIR} -p dist/Debug/GNU-MacOSX
	${LINK.cc} -o dist/Debug/GNU-MacOSX/application_1 ${OBJECTFILES} ${LDLIBSOPTIONS} 

${OBJECTDIR}/newmain.o: newmain.cpp 
	${MKDIR} -p ${OBJECTDIR}
	$(COMPILE.cc) -g -o ${OBJECTDIR}/newmain.o newmain.cpp

# Subprojects
.build-subprojects:

# Clean Targets
.clean-conf:
	${RM} -r build/Debug
	${RM} dist/Debug/GNU-MacOSX/application_1

# Subprojects
.clean-subprojects:
