//{{NO_DEPENDENCIES}}
// Microsoft Visual C++ generated include file.
// Used by OptiScaler.rc
//

#define VS_VERSION_INFO 1

// Next default values for new objects
//
#ifdef APSTUDIO_INVOKED
#ifndef APSTUDIO_READONLY_SYMBOLS
#define _APS_NEXT_RESOURCE_VALUE 101
#define _APS_NEXT_COMMAND_VALUE 40001
#define _APS_NEXT_CONTROL_VALUE 1001
#define _APS_NEXT_SYMED_VALUE 101
#endif
#endif

#define STRINGIZE_(s) #s
#define STRINGIZE(s) STRINGIZE_(s)

#define VER_MAJOR_VERSION 10
#define VER_MINOR_VERSION 0
#define VER_HOTFIX_VERSION 0
#define VER_BUILD_NUMBER 1

// Aurora release version. Keep this separate from the upstream OptiScaler base version.
#define VER_AURORA_VERSION "1.0"

#define VER_DEV_RELEASE
// #define VER_PRE_RELEASE

// Follows the release suffix in every flavour of VER_PRODUCT_VERSION_STR. Adjacent literals
// concatenate, so an empty tag reproduces the upstream string byte for byte.
#ifndef VER_FORK_TAG
#define VER_FORK_TAG "-aurora-v1.0"
#endif

#define VER_FILE_VERSION VER_MAJOR_VERSION, VER_MINOR_VERSION, VER_HOTFIX_VERSION, VER_BUILD_NUMBER
#define VER_FILE_VERSION_STR                                                                                           \
    STRINGIZE(VER_MAJOR_VERSION) "." STRINGIZE(VER_MINOR_VERSION) "." STRINGIZE(VER_HOTFIX_VERSION) "." STRINGIZE(VER_BUILD_NUMBER)
#define OPTI_VERSION STRINGIZE(VER_MAJOR_VERSION) "." STRINGIZE(VER_MINOR_VERSION) "." STRINGIZE(VER_HOTFIX_VERSION)

#define VER_PRODUCT_VERSION VER_FILE_VERSION

#ifdef OPTISCALER_BUILD_METADATA
#ifdef _DEBUG
#define VER_BUILD_DATE "Debug Build"
#define VER_BUILD_COMMIT "Debug"
#else
#include "resource_build_date.h"
#include "resource_build_commit.h"
#endif // !_DEBUG

#ifdef VER_DEV_RELEASE
#define VER_PRODUCT_VERSION_STR                                                                                        \
    STRINGIZE(VER_MAJOR_VERSION) "." STRINGIZE(VER_MINOR_VERSION) "." STRINGIZE(VER_HOTFIX_VERSION) "-dev" VER_FORK_TAG " (" VER_BUILD_COMMIT ") (" VER_BUILD_DATE ")"
#elif VER_PRE_RELEASE
#define VER_PRODUCT_VERSION_STR                                                                                        \
    STRINGIZE(VER_MAJOR_VERSION) "." STRINGIZE(VER_MINOR_VERSION) "." STRINGIZE(VER_HOTFIX_VERSION) "-pre" STRINGIZE(VER_BUILD_NUMBER) VER_FORK_TAG " (" VER_BUILD_COMMIT ") (" VER_BUILD_DATE ")"
#else
#define VER_PRODUCT_VERSION_STR                                                                                        \
    STRINGIZE(VER_MAJOR_VERSION) "." STRINGIZE(VER_MINOR_VERSION) "." STRINGIZE(VER_HOTFIX_VERSION) "-final" VER_FORK_TAG " (" VER_BUILD_COMMIT ")"
#endif // VER_PRE_RELEASE

#define VER_PRODUCT_NAME "OptiScaler Aurora v" VER_AURORA_VERSION

#endif // OPTISCALER_BUILD_METADATA
