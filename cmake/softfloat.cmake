
# softfloat: floating point arithmetic library 
CPMAddPackage(
  NAME softfloat
  GITHUB_REPOSITORY ucb-bar/berkeley-softfloat-3
  GIT_TAG master
  DOWNLOAD_ONLY YES
  EXCLUDE_FROM_ALL True
  SYSTEM True)

# IMPORTANT: since official GitHub doesn't use cmake, integrating purely with
# CPM is impossible.

# Has to be generaterd to avoid using softfloat's makefiles in order to keep
# everything in one build system
set(SOFTFLOAT_PLATFORM_H ${CMAKE_CURRENT_BINARY_DIR}/platform.h)

file(WRITE ${SOFTFLOAT_PLATFORM_H}
"#ifndef SOFTFLOAT_PLATFORM_H
#define SOFTFLOAT_PLATFORM_H

#include <stdint.h>
#include <stdbool.h>

#endif
")

file(GLOB SOFTFLOAT_SRC
  ${softfloat_SOURCE_DIR}/source/*.c
)

list(FILTER SOFTFLOAT_SRC EXCLUDE REGEX ".*F80*")
list(FILTER SOFTFLOAT_SRC EXCLUDE REGEX ".*F128*")
list(FILTER SOFTFLOAT_SRC EXCLUDE REGEX ".*bf16*")
list(FILTER SOFTFLOAT_SRC EXCLUDE REGEX ".*f16_*")

add_library(softfloat STATIC ${SOFTFLOAT_SRC})

target_include_directories(softfloat PUBLIC
  ${softfloat_SOURCE_DIR}/source/include
  ${softfloat_SOURCE_DIR}/build/Linux-x86_64-GCC
  ${softfloat_SOURCE_DIR}/source/8086
  ${CMAKE_CURRENT_BINARY_DIR}
)

target_compile_definitions(softfloat PRIVATE SOFTFLOAT_FAST_INT64)
