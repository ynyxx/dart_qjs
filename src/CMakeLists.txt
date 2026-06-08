cmake_minimum_required(VERSION 3.14)
set(CXX_LIB_DIR ${CMAKE_CURRENT_LIST_DIR})
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

project(quickjs LANGUAGES C CXX)

include(CheckCCompilerFlag)
find_package(Threads)

set(DART_QJS_OUTPUT_NAME flutter_qjs_plugin)

# quickjs
set(QUICK_JS_LIB_DIR ${CXX_LIB_DIR}/quickjs)
add_library(quickjs SHARED
  ${QUICK_JS_LIB_DIR}/dtoa.c
    ${QUICK_JS_LIB_DIR}/libregexp.c
    ${QUICK_JS_LIB_DIR}/libunicode.c
    ${QUICK_JS_LIB_DIR}/quickjs.c
    ffi.cpp
)

target_include_directories(quickjs PRIVATE
    "${QJS_SOURCE_DIR_CMAKE}"
    "${QJS_SOURCE_DIR_CMAKE}/quickjs"
)

target_compile_definitions(quickjs PRIVATE
  DUMP_LEAKS
  QUICKJS_NG_BUILD
  _GNU_SOURCE
)

if(WIN32)
  target_compile_definitions(quickjs PRIVATE
    WIN32_LEAN_AND_MEAN
    _WIN32_WINNT=0x0601
  )
endif()

target_link_libraries(quickjs PRIVATE
  ${CMAKE_DL_LIBS}
  ${CMAKE_THREAD_LIBS_INIT}
)

if(MSVC)
    # https://github.com/ekibun/flutter_qjs/issues/7
    target_compile_options(quickjs PRIVATE "/Oi-")
  target_compile_options(quickjs PRIVATE "/experimental:c11atomics")
endif()

set_target_properties(quickjs PROPERTIES
  PUBLIC_HEADER ffi.h
  OUTPUT_NAME "${DART_QJS_OUTPUT_NAME}"
)

target_compile_definitions(quickjs PUBLIC DART_SHARED_LIB)

if(ANDROID)
  # Support Android 15 16k page size.
  target_link_options(quickjs PRIVATE "-Wl,-z,max-page-size=16384")
endif()

install(TARGETS quickjs
  RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}/lib"
  LIBRARY DESTINATION "${CMAKE_INSTALL_PREFIX}/lib"
  PUBLIC_HEADER DESTINATION "${CMAKE_INSTALL_PREFIX}/include"
)
