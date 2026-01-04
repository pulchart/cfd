/*
 * common.h - Common macros and definitions
 *
 * Shared macros used across multiple tools in the compactflash.device project
 */

#ifndef COMMON_H
#define COMMON_H

/* Version and date must be defined by build system */
#ifndef VERSION
#error "VERSION not defined - build with Makefile"
#endif
#ifndef DATE
#error "DATE not defined - build with Makefile"
#endif

/* Version string generation macros */
#define STR_HELPER(x) #x
#define STR(x) STR_HELPER(x)

/* Version string template - requires VERSION and DATE to be defined */
#define MAKE_VERSION_STRING(toolname) \
    "$VER: " toolname " " STR(VERSION) " (" STR(DATE) ")"

#endif /* COMMON_H */