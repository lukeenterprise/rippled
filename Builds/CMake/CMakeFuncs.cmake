# This is a set of common functions and settings for rippled
# and derived products.

############################################################

cmake_minimum_required(VERSION 3.1.0)

if("${CMAKE_SOURCE_DIR}" STREQUAL "${CMAKE_BINARY_DIR}")
  message(WARNING "Builds are strongly discouraged in "
    "${CMAKE_SOURCE_DIR}.")
endif()

macro(parse_target)

  if (NOT target AND NOT CMAKE_BUILD_TYPE)
    if (APPLE)
      set(target clang.debug)
    elseif(WIN32)
      set(target msvc)
    else()
      set(target gcc.debug)
    endif()
  endif()

  if (target)
    # Parse the target
    set(remaining ${target})
    while (remaining)
      # get the component up to the next dot or end
      string(REGEX REPLACE "^\\.?([^\\.]+).*$" "\\1" cur_component ${remaining})
      string(REGEX REPLACE "^\\.?[^\\.]+(.*$)" "\\1" remaining ${remaining})

      if (${cur_component} STREQUAL gcc)
        if (DEFINED ENV{GNU_CC})
          set(CMAKE_C_COMPILER $ENV{GNU_CC})
        elseif ($ENV{CXX} MATCHES .*gcc.*)
          set(CMAKE_CXX_COMPILER $ENV{CC})
        else()
          find_program(CMAKE_C_COMPILER gcc)
        endif()

        if (DEFINED ENV{GNU_CXX})
          set(CMAKE_C_COMPILER $ENV{GNU_CXX})
        elseif ($ENV{CXX} MATCHES .*g\\+\\+.*)
          set(CMAKE_C_COMPILER $ENV{CC})
        else()
          find_program(CMAKE_CXX_COMPILER g++)
        endif()
      endif()

      if (${cur_component} STREQUAL clang)
        if (DEFINED ENV{CLANG_CC})
          set(CMAKE_C_COMPILER $ENV{CLANG_CC})
        elseif ($ENV{CXX} MATCHES .*clang.*)
          set(CMAKE_CXX_COMPILER $ENV{CC})
        else()
          find_program(CMAKE_C_COMPILER clang)
        endif()

        if (DEFINED ENV{CLANG_CXX})
          set(CMAKE_C_COMPILER $ENV{CLANG_CXX})
        elseif ($ENV{CXX} MATCHES .*clang.*)
          set(CMAKE_C_COMPILER $ENV{CC})
        else()
          find_program(CMAKE_CXX_COMPILER clang++)
        endif()
      endif()

      if (${cur_component} STREQUAL msvc)
        # TBD
      endif()

      if (${cur_component} STREQUAL unity)
        set(unity true)
        set(nonunity false)
      endif()

      if (${cur_component} STREQUAL nounity)
        set(unity false)
        set(nonunity true)
      endif()

      if (${cur_component} STREQUAL debug)
        set(release false)
      endif()

      if (${cur_component} STREQUAL release)
        set(release true)
      endif()

      if (${cur_component} STREQUAL coverage)
        set(coverage true)
        set(debug true)
      endif()

      if (${cur_component} STREQUAL profile)
        set(profile true)
      endif()

      if (${cur_component} STREQUAL ci)
        # Workarounds that make various CI builds work, but that
        # we don't want in the general case.
        set(ci true)
        set(openssl_min 1.0.1)
      endif()

    endwhile()

    if (release)
      set(CMAKE_BUILD_TYPE Release)
    else()
      set(CMAKE_BUILD_TYPE Debug)
    endif()

    if (NOT unity)
      set(CMAKE_BUILD_TYPE ${CMAKE_BUILD_TYPE}Classic)
    endif()
  endif()

endmacro()

############################################################

macro(setup_build_cache)
  set(san "" CACHE STRING "On gcc & clang, add sanitizer
    instrumentation")
  set_property(CACHE san PROPERTY STRINGS ";address;thread")
  set(assert false CACHE BOOL "Enables asserts, even in release builds")
  set(static false CACHE BOOL
    "On linux, link protobuf, openssl, libc++, and boost statically")

  if (static AND (WIN32 OR APPLE))
    message(FATAL_ERROR "Static linking is only supported on linux.")
  endif()

  if (${CMAKE_GENERATOR} STREQUAL "Unix Makefiles" AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug)
  endif()

  # Can't exclude files from configurations, so can't support both
  # unity and nonunity configurations at the same time
  if (NOT DEFINED unity OR unity)
    set(CMAKE_CONFIGURATION_TYPES
      Debug
      Release)
  else()
    set(CMAKE_CONFIGURATION_TYPES
      DebugClassic
      ReleaseClassic)
  endif()

  set(CMAKE_CONFIGURATION_TYPES
    ${CMAKE_CONFIGURATION_TYPES} CACHE STRING "" FORCE)
endmacro()

############################################################

function(prepend var prefix)
  set(listVar "")
  foreach(f ${ARGN})
    list(APPEND listVar "${prefix}${f}")
  endforeach(f)
  set(${var} "${listVar}" PARENT_SCOPE)
endfunction()

macro(append_flags name)
  foreach (arg ${ARGN})
    set(${name} "${${name}} ${arg}")
  endforeach()
endmacro()

macro(group_sources curdir)
  file(GLOB children RELATIVE ${PROJECT_SOURCE_DIR}/${curdir}
    ${PROJECT_SOURCE_DIR}/${curdir}/*)
  foreach (child ${children})
    if (IS_DIRECTORY ${PROJECT_SOURCE_DIR}/${curdir}/${child})
      group_sources(${curdir}/${child})
    else()
      string(REPLACE "/" "\\" groupname ${curdir})
      source_group(${groupname} FILES
        ${PROJECT_SOURCE_DIR}/${curdir}/${child})
    endif()
  endforeach()
endmacro()

macro(add_with_props src_var files)
  list(APPEND ${src_var} ${files})
  foreach (arg ${ARGN})
    set(props "${props} ${arg}")
  endforeach()
  set_source_files_properties(
    ${files}
    PROPERTIES COMPILE_FLAGS
    ${props})
endmacro()

############################################################

macro(determine_build_type)
  if ("${CMAKE_CXX_COMPILER_ID}" MATCHES ".*Clang") # both Clang and AppleClang
    set(is_clang true)
  elseif ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU")
    set(is_gcc true)
  elseif ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC")
    set(is_msvc true)
  endif()

  if (${CMAKE_GENERATOR} STREQUAL "Xcode")
    set(is_xcode true)
  else()
    set(is_xcode false)
  endif()

  if (NOT is_gcc AND NOT is_clang AND NOT is_msvc)
    message("Current compiler is ${CMAKE_CXX_COMPILER_ID}")
    message(FATAL_ERROR "Missing compiler. Must be GNU, Clang, or MSVC")
  endif()
endmacro()

############################################################

macro(check_gcc4_abi)
  # Check if should use gcc4's ABI
  set(gcc4_abi false)

  if ($ENV{RIPPLED_OLD_GCC_ABI})
    set(gcc4_abi true)
  endif()

  if (is_gcc AND NOT gcc4_abi)
    if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER 5)
      execute_process(COMMAND lsb_release -si OUTPUT_VARIABLE lsb)
      string(STRIP ${lsb} lsb)
      if (${lsb} STREQUAL "Ubuntu")
        execute_process(COMMAND lsb_release -sr OUTPUT_VARIABLE lsb)
        string(STRIP ${lsb} lsb)
        if (${lsb} VERSION_LESS 15.1)
          set(gcc4_abi true)
        endif()
      endif()
    endif()
  endif()

  if (gcc4_abi)
    add_definitions(-D_GLIBCXX_USE_CXX11_ABI=0)
  endif()
endmacro()

############################################################

macro(special_build_flags)
  if (coverage)
    add_compile_options(-fprofile-arcs -ftest-coverage)
    append_flags(CMAKE_EXE_LINKER_FLAGS -fprofile-arcs -ftest-coverage)
  endif()

  if (profile)
    add_compile_options(-p -pg)
    append_flags(CMAKE_EXE_LINKER_FLAGS -p -pg)
  endif()
endmacro()

############################################################

# Params: Boost components to search for.
macro(find_boost)
  if (NOT WIN32)
    if (is_clang AND DEFINED ENV{CLANG_BOOST_ROOT})
      set(BOOST_ROOT $ENV{CLANG_BOOST_ROOT})
    endif()

    set(Boost_USE_STATIC_LIBS on)
    set(Boost_USE_MULTITHREADED on)
    set(Boost_USE_STATIC_RUNTIME off)
    find_package(Boost COMPONENTS
      ${ARGN})

    if (Boost_FOUND)
      include_directories(SYSTEM ${Boost_INCLUDE_DIRS})
    else()
      message(FATAL_ERROR "Boost not found")
    endif()
  else(DEFINED ENV{BOOST_ROOT})
    include_directories(SYSTEM $ENV{BOOST_ROOT})
    link_directories($ENV{BOOST_ROOT}/stage/lib)
  endif()
endmacro()

macro(find_pthread)
  if (NOT WIN32)
    set(THREADS_PREFER_PTHREAD_FLAG ON)
    find_package(Threads)
  endif()
endmacro()

macro(find_openssl openssl_min)
  if (APPLE)
    # swd TBD fixme
    file(GLOB OPENSSL_ROOT_DIR /usr/local/Cellar/openssl/*)
    # set(OPENSSL_ROOT_DIR /usr/local/Cellar/openssl)
  endif()

  if (WIN32)
    if (DEFINED ENV{OPENSSL_ROOT})
      include_directories($ENV{OPENSSL_ROOT}/include)
      link_directories($ENV{OPENSSL_ROOT}/lib)
    endif()
  else()
    if (static)
      set(tmp CMAKE_FIND_LIBRARY_SUFFIXES)
      set(CMAKE_FIND_LIBRARY_SUFFIXES .a)
    endif()

    find_package(OpenSSL)

    if (static)
      set(CMAKE_FIND_LIBRARY_SUFFIXES tmp)
    endif()

    if (OPENSSL_FOUND)
      include_directories(${OPENSSL_INCLUDE_DIR})
    else()
      message(FATAL_ERROR "OpenSSL not found")
    endif()
    if (UNIX AND NOT APPLE AND ${OPENSSL_VERSION} VERSION_LESS ${openssl_min})
      message(FATAL_ERROR
        "Your openssl is Version: ${OPENSSL_VERSION}, ${openssl_min} or better is required.")
    endif()
  endif()
endmacro()

macro(find_protobuf)
  if (WIN32)
    if (DEFINED ENV{PROTOBUF_ROOT})
      include_directories($ENV{PROTOBUF_ROOT}/src)
      link_directories($ENV{PROTOBUF_ROOT}/src/.libs)
    endif()

    # Modified from FindProtobuf.cmake
    FUNCTION(PROTOBUF_GENERATE_CPP SRCS HDRS PROTOFILES)
      # argument parsing
      IF(NOT PROTOFILES)
        MESSAGE(SEND_ERROR "Error: PROTOBUF_GENERATE_CPP() called without any proto files")
        RETURN()
      ENDIF()

      SET(OUTPATH ${CMAKE_CURRENT_BINARY_DIR})
      SET(PROTOROOT ${CMAKE_CURRENT_SOURCE_DIR})
      # the real logic
      SET(${SRCS})
      SET(${HDRS})
      FOREACH(PROTOFILE ${PROTOFILES})
        # ensure that the file ends with .proto
        STRING(REGEX MATCH "\\.proto$$" PROTOEND ${PROTOFILE})
        IF(NOT PROTOEND)
          MESSAGE(SEND_ERROR "Proto file '${PROTOFILE}' does not end with .proto")
        ENDIF()

        GET_FILENAME_COMPONENT(PROTO_PATH ${PROTOFILE} PATH)
        GET_FILENAME_COMPONENT(ABS_FILE ${PROTOFILE} ABSOLUTE)
        GET_FILENAME_COMPONENT(FILE_WE ${PROTOFILE} NAME_WE)

        STRING(REGEX MATCH "^${PROTOROOT}" IN_ROOT_PATH ${PROTOFILE})
        STRING(REGEX MATCH "^${PROTOROOT}" IN_ROOT_ABS_FILE ${ABS_FILE})

        IF(IN_ROOT_PATH)
          SET(MATCH_PATH ${PROTOFILE})
        ELSEIF(IN_ROOT_ABS_FILE)
          SET(MATCH_PATH ${ABS_FILE})
        ELSE()
          MESSAGE(SEND_ERROR "Proto file '${PROTOFILE}' is not in protoroot '${PROTOROOT}'")
        ENDIF()

        # build the result file name
        STRING(REGEX REPLACE "^${PROTOROOT}(/?)" "" ROOT_CLEANED_FILE ${MATCH_PATH})
        STRING(REGEX REPLACE "\\.proto$$" "" EXT_CLEANED_FILE ${ROOT_CLEANED_FILE})

        SET(CPP_FILE "${OUTPATH}/${EXT_CLEANED_FILE}.pb.cc")
        SET(H_FILE "${OUTPATH}/${EXT_CLEANED_FILE}.pb.h")

        LIST(APPEND ${SRCS} "${CPP_FILE}")
        LIST(APPEND ${HDRS} "${H_FILE}")

        ADD_CUSTOM_COMMAND(
          OUTPUT "${CPP_FILE}" "${H_FILE}"
          COMMAND ${CMAKE_COMMAND} -E make_directory ${OUTPATH}
          COMMAND ${PROTOBUF_PROTOC_EXECUTABLE}
          ARGS "--cpp_out=${OUTPATH}" --proto_path "${PROTOROOT}" "${MATCH_PATH}"
          DEPENDS ${ABS_FILE}
          COMMENT "Running C++ protocol buffer compiler on ${MATCH_PATH} with root ${PROTOROOT}, generating: ${CPP_FILE}"
          VERBATIM)

      ENDFOREACH()

      SET_SOURCE_FILES_PROPERTIES(${${SRCS}} ${${HDRS}} PROPERTIES GENERATED TRUE)
      SET(${SRCS} ${${SRCS}} PARENT_SCOPE)
      SET(${HDRS} ${${HDRS}} PARENT_SCOPE)

    ENDFUNCTION()

    set(PROTOBUF_PROTOC_EXECUTABLE Protoc) # must be on path
  else()
    if (static)
      set(tmp CMAKE_FIND_LIBRARY_SUFFIXES)
      set(CMAKE_FIND_LIBRARY_SUFFIXES .a)
    endif()

    find_package(Protobuf REQUIRED)

    if (static)
      set(CMAKE_FIND_LIBRARY_SUFFIXES tmp)
    endif()

    if (is_clang AND DEFINED ENV{CLANG_PROTOBUF_ROOT})
      link_directories($ENV{CLANG_PROTOBUF_ROOT}/src/.libs)
      include_directories($ENV{CLANG_PROTOBUF_ROOT}/src)
    else()
      include_directories(${PROTOBUF_INCLUDE_DIRS})
    endif()
  endif()
  include_directories(${CMAKE_CURRENT_BINARY_DIR})

  file(GLOB ripple_proto src/ripple/proto/*.proto)
  PROTOBUF_GENERATE_CPP(PROTO_SRCS PROTO_HDRS ${ripple_proto})

  if (WIN32)
    include_directories(src/protobuf/src
      src/protobuf/vsprojects
      ${CMAKE_CURRENT_BINARY_DIR}/src/ripple/proto)
  endif()

endmacro()

############################################################

macro(setup_build_boilerplate)
  if (NOT WIN32 AND san)
    add_compile_options(-fsanitize=${san} -fno-omit-frame-pointer)

    append_flags(CMAKE_EXE_LINKER_FLAGS
      -fsanitize=${san})

    string(TOLOWER ${san} ci_san)
    if (${ci_san} STREQUAL address)
      set(SANITIZER_LIBRARIES asan)
      add_definitions(-DSANITIZER=ASAN)
    endif()
    if (${ci_san} STREQUAL thread)
      set(SANITIZER_LIBRARIES tsan)
      add_definitions(-DSANITIZER=TSAN)
    endif()
  endif()

  ############################################################

  add_definitions(
    -DOPENSSL_NO_SSL2
    -DDEPRECATED_IN_MAC_OS_X_VERSION_10_7_AND_LATER
    -DHAVE_USLEEP=1
    -DSOCI_CXX_C11=1
    -D_SILENCE_STDEXT_HASH_DEPRECATION_WARNINGS
    -DBOOST_NO_AUTO_PTR
    )

  if (is_gcc)
    add_compile_options(-Wno-unused-but-set-variable -Wno-deprecated)
  endif()

  # Generator expressions are not supported in add_definitions, use set_property instead
  set_property(
    DIRECTORY
    APPEND
    PROPERTY COMPILE_DEFINITIONS
    $<$<OR:$<CONFIG:Debug>,$<CONFIG:DebugClassic>>:DEBUG _DEBUG>)

  if (NOT assert)
    set_property(
      DIRECTORY
      APPEND
      PROPERTY COMPILE_DEFINITIONS
      $<$<OR:$<BOOL:${profile}>,$<CONFIG:Release>,$<CONFIG:ReleaseClassic>>:NDEBUG>)
  endif()

  if (NOT WIN32)
    add_definitions(-D_FILE_OFFSET_BITS=64)
    append_flags(CMAKE_CXX_FLAGS -frtti -std=c++14 -Wno-invalid-offsetof
      -DBOOST_COROUTINE_NO_DEPRECATION_WARNING -DBOOST_COROUTINES_NO_DEPRECATION_WARNING)
    add_compile_options(-Wall -Wno-sign-compare -Wno-char-subscripts -Wno-format
      -Wno-unused-local-typedefs -g)
    # There seems to be an issue using generator experssions with multiple values,
    # split the expression
    add_compile_options($<$<OR:$<CONFIG:Release>,$<CONFIG:ReleaseClassic>>:-O3>)
    add_compile_options($<$<OR:$<CONFIG:Release>,$<CONFIG:ReleaseClassic>>:-fno-strict-aliasing>)
    append_flags(CMAKE_EXE_LINKER_FLAGS -rdynamic -g)

    if (is_clang)
      add_compile_options(
        -Wno-redeclared-class-member -Wno-mismatched-tags -Wno-deprecated-register)
      add_definitions(-DBOOST_ASIO_HAS_STD_ARRAY)
    endif()

    if (APPLE)
      add_definitions(-DBEAST_COMPILE_OBJECTIVE_CPP=1
        -DNO_LOG_UNHANDLED_EXCEPTIONS)
      add_compile_options(
        -Wno-deprecated -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function)
    endif()

    if (is_gcc)
      add_compile_options(-Wno-unused-but-set-variable -Wno-unused-local-typedefs)
      add_compile_options($<$<OR:$<CONFIG:Debug>,$<CONFIG:DebugClassic>>:-O0>)
    endif (is_gcc)
  else(NOT WIN32)
    add_compile_options(
      /bigobj              # Increase object file max size
      /EHa                 # ExceptionHandling all
      /fp:precise          # Floating point behavior
      /Gd                  # __cdecl calling convention
      /Gm-                 # Minimal rebuild: disabled
      /GR                  # Enable RTTI
      /Gy-                 # Function level linking: disabled
      /FS
      /MP                  # Multiprocessor compilation
      /openmp-             # pragma omp: disabled
      /Zc:forScope         # Language extension: for scope
      /Zi                  # Generate complete debug info
      /errorReport:none    # No error reporting to Internet
      /nologo              # Suppress login banner
      /W3                  # Warning level 3
      /WX-                 # Disable warnings as errors
      /wd"4018"
      /wd"4244"
      /wd"4267"
      /wd"4800"            # Disable C4800(int to bool performance)
      /wd"4503"            # Decorated name length exceeded, name was truncated
      )
    add_definitions(
      -D_WIN32_WINNT=0x6000
      -D_SCL_SECURE_NO_WARNINGS
      -D_CRT_SECURE_NO_WARNINGS
      -DWIN32_CONSOLE
      -DNOMINMAX
      -DBOOST_COROUTINE_NO_DEPRECATION_WARNING
      -DBOOST_COROUTINES_NO_DEPRECATION_WARNING)
    append_flags(CMAKE_EXE_LINKER_FLAGS
      /DEBUG
      /DYNAMICBASE
      /ERRORREPORT:NONE
      /MACHINE:X64
      /MANIFEST
      /nologo
      /NXCOMPAT
      /SUBSYSTEM:CONSOLE
      /TLBID:1)


    # There seems to be an issue using generator experssions with multiple values,
    # split the expression
    # /GS  Buffers security check: enable
    add_compile_options($<$<OR:$<CONFIG:Debug>,$<CONFIG:DebugClassic>>:/GS>)
    # /MTd Language: Multi-threaded Debug CRT
    add_compile_options($<$<OR:$<CONFIG:Debug>,$<CONFIG:DebugClassic>>:/MTd>)
    # /Od  Optimization: Disabled
    add_compile_options($<$<OR:$<CONFIG:Debug>,$<CONFIG:DebugClassic>>:/Od>)
    # /RTC1 Run-time error checks:
    add_compile_options($<$<OR:$<CONFIG:Debug>,$<CONFIG:DebugClassic>>:/RTC1>)

    # Generator expressions are not supported in add_definitions, use set_property instead
    set_property(
      DIRECTORY
      APPEND
      PROPERTY COMPILE_DEFINITIONS
      $<$<OR:$<CONFIG:Debug>,$<CONFIG:DebugClassic>>:_CRTDBG_MAP_ALLOC>)

    # /MT Language: Multi-threaded CRT
    add_compile_options($<$<OR:$<CONFIG:Release>,$<CONFIG:ReleaseClassic>>:/MT>)
    add_compile_options($<$<OR:$<CONFIG:Release>,$<CONFIG:ReleaseClassic>>:/Ox>)
    # /Ox Optimization: Full

  endif (NOT WIN32)

  if (static)
    append_flags(CMAKE_EXE_LINKER_FLAGS -static-libstdc++)
    # set_target_properties(ripple-libpp PROPERTIES LINK_SEARCH_START_STATIC 1)
    # set_target_properties(ripple-libpp PROPERTIES LINK_SEARCH_END_STATIC 1)
  endif()
endmacro()

############################################################

macro(create_build_folder cur_project)
  if (NOT WIN32)
    ADD_CUSTOM_TARGET(build_folder ALL
      COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}
      COMMENT "Creating build output folder")
    add_dependencies(${cur_project} build_folder)
  endif()
endmacro()

macro(set_startup_project cur_project)
  if (WIN32 AND NOT ci)
    if (CMAKE_VERSION VERSION_LESS 3.6)
      message(WARNING
        "Setting the VS startup project requires cmake 3.6 or later. Please upgrade.")
    endif()
    set_property(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR} PROPERTY
      VS_STARTUP_PROJECT ${cur_project})
  endif()
endmacro()

macro(link_common_libraries cur_project)
  if (NOT WIN32)
    target_link_libraries(${cur_project} ${Boost_LIBRARIES})
    target_link_libraries(${cur_project} dl)
    target_link_libraries(${cur_project} Threads::Threads)
    if (APPLE)
      find_library(app_kit AppKit)
      find_library(foundation Foundation)
      target_link_libraries(${cur_project}
        crypto ssl ${app_kit} ${foundation})
    else()
      target_link_libraries(${cur_project} rt)
    endif()
  else(NOT WIN32)
    target_link_libraries(${cur_project}
      $<$<OR:$<CONFIG:Debug>,$<CONFIG:DebugClassic>>:VC/static/ssleay32MTd>
      $<$<OR:$<CONFIG:Debug>,$<CONFIG:DebugClassic>>:VC/static/libeay32MTd>)
    target_link_libraries(${cur_project}
      $<$<OR:$<CONFIG:Release>,$<CONFIG:ReleaseClassic>>:VC/static/ssleay32MT>
      $<$<OR:$<CONFIG:Release>,$<CONFIG:ReleaseClassic>>:VC/static/libeay32MT>)
    target_link_libraries(${cur_project}
      legacy_stdio_definitions.lib Shlwapi kernel32 user32 gdi32 winspool comdlg32
      advapi32 shell32 ole32 oleaut32 uuid odbc32 odbccp32)
  endif (NOT WIN32)
endmacro()