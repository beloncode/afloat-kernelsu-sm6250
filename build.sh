#!/usr/bin/env bash

KERNEL_DIR="$(pwd)"

MODEL=Xiaomi
DEVICE=Miatoll

DEFCONFIG=cust_defconfig

DISABLE_LTO=0
THIN_LTO=0

IMAGE=$(pwd)/out/arch/arm64/boot/Image.gz
DTBO=$(pwd)/out/arch/arm64/boot/dtbo.img
DTB=$(pwd)/out/arch/arm64/boot/dts/qcom/cust-atoll-ab.dtb

VERBOSE=0

KERVER="$(make kernelversion)"

COMMIT_SHORT_ID="$(git rev-parse --short HEAD)"
VENDOR_NAME="$(hostnamectl hostname)"

COMPILER=atomx
LINKER=ld.lld

FINAL_ZIP="${VENDOR_NAME}-kernel-${DEVICE}_${KERVER}-${COMMIT_SHORT_ID}.zip"

VERSION="${COMPILER},${LINKER}"

function cloneTC() {
    if [ -e clang ]; then
        PATH="${KERNEL_DIR}/clang/bin:$PATH"
        return
    elif [ -e gcc ]; then
        PATH="$PATH"
        return
    fi
	
    if [ $COMPILER = "atomx" ]; then
        git clone --depth=1 https://gitlab.com/ElectroPerf/atom-x-clang.git clang
        PATH="${KERNEL_DIR}/clang/bin:$PATH"
    elif [ $COMPILER = "neutron" ]; then
        git clone --depth=1 https://gitlab.com/dakkshesh07/neutron-clang.git clang
        PATH="${KERNEL_DIR}/clang/bin:$PATH"
    elif [ $COMPILER = "azure" ]; then
        git clone --depth=1 https://gitlab.com/ImSpiDy/azure-clang.git clang
        PATH="${KERNEL_DIR}/clang/bin:$PATH"
    elif [ $COMPILER = "proton" ]; then
        git clone --depth=1 https://github.com/kdrag0n/proton-clang.git clang
        PATH="${KERNEL_DIR}/clang/bin:$PATH"
    elif [ $COMPILER = "eva" ]; then
        git clone --depth=1 https://github.com/mvaisakh/gcc-arm64.git -b gcc-new gcc64
        git clone --depth=1 https://github.com/mvaisakh/gcc-arm.git -b gcc-new gcc32
        PATH=$KERNEL_DIR/gcc64/bin/:$KERNEL_DIR/gcc32/bin/:/usr/bin:$PATH
    elif [ $COMPILER = "aosp" ]; then
        mkdir aosp-clang
        cd aosp-clang || exit
        wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master/clang-r450784b.tar.gz
        tar -xf clang*
        cd .. || exit
        git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git --depth=1 gcc
        git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9.git  --depth=1 gcc32
        PATH="${KERNEL_DIR}/aosp-clang/bin:${KERNEL_DIR}/gcc/bin:${KERNEL_DIR}/gcc32/bin:${PATH}"
    fi
    
    if ![ -e afloat-kernel]; then
        git clone --depth=1 https://github.com/beloncode/afloat-kernel.git
    fi

}

function exports() {
    if [ -d ${KERNEL_DIR}/clang ]; then
        export KBUILD_COMPILER_STRING=$(${KERNEL_DIR}/clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
    elif [ -d ${KERNEL_DIR}/gcc64 ]; then
        export KBUILD_COMPILER_STRING=$("$KERNEL_DIR/gcc64"/bin/aarch64-elf-gcc --version | head -n 1)
    elif [ -d ${KERNEL_DIR}/aosp-clang ]; then
        export KBUILD_COMPILER_STRING=$(${KERNEL_DIR}/aosp-clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
    fi

    export ARCH=arm64
    export SUBARCH=arm64
    
    export LOCALVERSION="-${VERSION}"
    
    export KBUILD_BUILD_HOST=Debian
    export KBUILD_BUILD_USER=Afloat

    if [ "$CI" ]; then
        if [ "$CIRCLECI" ]; then
            export KBUILD_BUILD_VERSION=${CIRCLE_BUILD_NUM}
            export CI_BRANCH=${CIRCLE_BRANCH}
        elif [ "$DRONE" ]; then
            export KBUILD_BUILD_VERSION=${DRONE_BUILD_NUMBER}
            export CI_BRANCH=${DRONE_BRANCH}
        fi
    fi
}

function configs() {
    if [ -d ${KERNEL_DIR}/clang ] || [ -d ${KERNEL_DIR}/aosp-clang ]; then
        if [ $DISABLE_LTO = "1" ]; then
            sed -i 's/CONFIG_LTO_CLANG=y/# CONFIG_LTO_CLANG is not set/' arch/arm64/configs/cust_defconfig
            sed -i 's/CONFIG_LTO=y/# CONFIG_LTO is not set/' arch/arm64/configs/cust_defconfig
            sed -i 's/# CONFIG_LTO_NONE is not set/CONFIG_LTO_NONE=y/' arch/arm64/configs/cust_defconfig
        elif [ $THIN_LTO = "1" ]; then
            sed -i 's/# CONFIG_THINLTO is not set/CONFIG_THINLTO=y/' arch/arm64/configs/cust_defconfig
        fi
    elif [ -d ${KERNEL_DIR}/gcc64 ]; then
        sed -i 's/CONFIG_LLVM_POLLY=y/# CONFIG_LLVM_POLLY is not set/' arch/arm64/configs/cust_defconfig
        sed -i 's/# CONFIG_GCC_GRAPHITE is not set/CONFIG_GCC_GRAPHITE=y/' arch/arm64/configs/cust_defconfig
        if ! [ $DISABLE_LTO = "1" ]; then
            sed -i 's/# CONFIG_LTO_GCC is not set/CONFIG_LTO_GCC=y/' arch/arm64/configs/cust_defconfig
        fi
    fi
}

function compile() {
    make O=out ${DEFCONFIG}
    if [ -d ${KERNEL_DIR}/clang ]; then
        make -kj$(nproc --all) O=out \
            ARCH=arm64 \
            CC=clang \
            HOSTCC=clang \
            HOSTCXX=clang++ \
            CROSS_COMPILE=aarch64-linux-gnu- \
            CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
            LD=${LINKER} \
            AR=llvm-ar \
            NM=llvm-nm \
            OBJCOPY=llvm-objcopy \
            OBJDUMP=llvm-objdump \
            STRIP=llvm-strip \
            READELF=llvm-readelf \
            OBJSIZE=llvm-size \
            V=$VERBOSE 2>&1 | tee error.log
    elif [ -d ${KERNEL_DIR}/gcc64 ]; then
        make -kj$(nproc --all) O=out \
            ARCH=arm64 \
            CROSS_COMPILE_ARM32=arm-eabi- \
            CROSS_COMPILE=aarch64-elf- \
            LD=aarch64-elf-${LINKER} \
            AR=llvm-ar \
            NM=llvm-nm \
            OBJCOPY=llvm-objcopy \
            OBJDUMP=llvm-objdump \
            STRIP=llvm-strip \
            OBJSIZE=llvm-size \
            V=$VERBOSE 2>&1 | tee error.log
    elif [ -d ${KERNEL_DIR}/aosp-clang ]; then
        make -kj$(nproc --all) O=out \
            ARCH=arm64 \
            CC=clang \
            HOSTCC=clang \
            HOSTCXX=clang++ \
            CLANG_TRIPLE=aarch64-linux-gnu- \
            CROSS_COMPILE=aarch64-linux-android- \
            CROSS_COMPILE_ARM32=arm-linux-androideabi- \
            LD=${LINKER} \
            AR=llvm-ar \
            NM=llvm-nm \
            OBJCOPY=llvm-objcopy \
            OBJDUMP=llvm-objdump \
            STRIP=llvm-strip \
            READELF=llvm-readelf \
            OBJSIZE=llvm-size \
            V=$VERBOSE 2>&1 | tee error.log
    fi
}

function zipping() {
    cp $IMAGE afloat-anykernel3
    cp $DTBO afloat-anykernel3
    cp $DTB afloat-anykernel3/dtb

    cd afloat-anykernel3 || exit 1
    
    zip -r9 ${FINAL_ZIP} *
    
    SHASUM_CHECKS=$(shasum -a256 "$FINAL_ZIP")
    
    mv $FINAL_ZIP "../dist/$FINAL_ZIP"
    echo $SHASUM_CHECKS >> "../dist/finalzips.check"
    
    cd ..
}

cloneTC
exports
configs
compile
zipping


