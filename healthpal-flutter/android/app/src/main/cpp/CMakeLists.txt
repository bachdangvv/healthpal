cmake_minimum_required(VERSION 3.22.1)
project(healthpal_native)

if(NOT ANDROID)
    return()
endif()

if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(RUST_TARGET aarch64-linux-android)
    set(CLANG_TRIPLE aarch64-linux-android)
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    set(RUST_TARGET armv7-linux-androideabi)
    set(CLANG_TRIPLE armv7a-linux-androideabi)
elseif(ANDROID_ABI STREQUAL "x86_64")
    set(RUST_TARGET x86_64-linux-android)
    set(CLANG_TRIPLE x86_64-linux-android)
else()
    message(FATAL_ERROR "Unsupported Android ABI ${ANDROID_ABI}")
endif()

set(ANDROID_API 26)
set(RUST_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../rust")
set(RUST_LIB "${RUST_DIR}/target/${RUST_TARGET}/release/libhealthpal_core.so")

if(CMAKE_HOST_WIN32)
    set(NDK_HOST windows-x86_64)
    set(CLANG_SUFFIX ".cmd")
    set(AR_NAME llvm-ar.exe)
else()
    if(CMAKE_HOST_APPLE)
        set(NDK_HOST darwin-x86_64)
    else()
        set(NDK_HOST linux-x86_64)
    endif()
    set(CLANG_SUFFIX "")
    set(AR_NAME llvm-ar)
endif()

set(LLVM_BIN "${ANDROID_NDK}/toolchains/llvm/prebuilt/${NDK_HOST}/bin")
set(CLANG "${LLVM_BIN}/${CLANG_TRIPLE}${ANDROID_API}-clang${CLANG_SUFFIX}")
set(AR "${LLVM_BIN}/${AR_NAME}")

string(REPLACE "-" "_" TARGET_ENV "${RUST_TARGET}")
string(TOUPPER "${TARGET_ENV}" TARGET_ENV_UPPER)

find_program(CARGO_EXECUTABLE cargo HINTS "$ENV{USERPROFILE}/.cargo/bin" "$ENV{HOME}/.cargo/bin" REQUIRED)

# pyke ort ships Android prebuilts only for arm64. Other ABIs run the frozen
# mobile graph with the exported float32 weights instead of ONNX Runtime.
if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(CARGO_FEATURES --features ort-runtime)
else()
    set(CARGO_FEATURES --no-default-features)
endif()

add_custom_command(
    OUTPUT "${RUST_LIB}"
    COMMAND "${CMAKE_COMMAND}" -E env
        "CARGO_TARGET_${TARGET_ENV_UPPER}_LINKER=${CLANG}"
        "CC_${TARGET_ENV}=${CLANG}"
        "AR_${TARGET_ENV}=${AR}"
        "ANDROID_NDK_HOME=${ANDROID_NDK}"
        "${CARGO_EXECUTABLE}" build --release --lib --target "${RUST_TARGET}" ${CARGO_FEATURES}
    WORKING_DIRECTORY "${RUST_DIR}"
    COMMENT "Building HealthPal Rust library for ${ANDROID_ABI}"
    VERBATIM
)

add_custom_target(healthpal_core_cargo DEPENDS "${RUST_LIB}")

add_library(healthpal_core SHARED placeholder.c)
add_dependencies(healthpal_core healthpal_core_cargo)
add_custom_command(
    TARGET healthpal_core
    POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${RUST_LIB}" "$<TARGET_FILE:healthpal_core>"
    COMMENT "Packaging libhealthpal_core.so for ${ANDROID_ABI}"
)
