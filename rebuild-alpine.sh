#!/usr/bin/env bash
# Alpine rebuild script for amlogic-s9xxx-alpine
# Based on ophub/amlogic-s9xxx-armbian rebuild
# Usage: sudo ./rebuild-alpine.sh -b s905x3 -k 6.1.y -t ext4

set -e

# ────────────────────────────────────────────────────────────────────────────────
#  基本变量（可通过参数覆盖，与原 rebuild 兼容）
# ────────────────────────────────────────────────────────────────────────────────
current_path="${PWD}"
armbian_outputpath="${current_path}/build/output/images"
build_path="${current_path}/build-armbian"
kernel_path="${build_path}/kernel"
uboot_path="${build_path}/u-boot"
common_files="${build_path}/armbian-files/common-files"
platform_files="${build_path}/armbian-files/platform-files"
different_files="${build_path}/armbian-files/different-files"
model_conf="${common_files}/etc/model_database.conf"
tmp_dir="${current_path}/build/tmp_dir"
tmp_outpath="${tmp_dir}/tmp_out"
tmp_armbian="${tmp_dir}/tmp_armbian"
tmp_build="${tmp_dir}/tmp_build"

# Alpine 配置
ALPINE_VERSION="3.23"
ALPINE_ARCH="aarch64"
ALPINE_MINIROOTFS="alpine-minirootfs-${ALPINE_VERSION}.3-${ALPINE_ARCH}.tar.gz"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ALPINE_ARCH}/${ALPINE_MINIROOTFS}"

# 默认参数（与原 rebuild 一致）
build_board="all"
kernel_usage="stable"
auto_kernel="true"
rootfs_type="ext4"
boot_mb=512
root_mb=3000
builder_name="alpine-custom"

# 颜色定义（复制原脚本）
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"

error_msg() { echo -e "${ERROR} ${1}"; exit 1; }
process_msg() { echo -e "${INFO} ${1}"; }

# ────────────────────────────────────────────────────────────────────────────────
#  参数解析（基本兼容原 rebuild 的 -b -k -t -a 等）
# ────────────────────────────────────────────────────────────────────────────────
init_var() {
    local options="b:k:t:a:s:n:"
    parsed_args=$(getopt -o "${options}" -- "${@}")
    eval set -- "${parsed_args}"

    while true; do
        case "${1}" in
            -b) build_board="${2}"; shift 2 ;;
            -k) kernel_list=(${2//_/ }); shift 2 ;;
            -t) rootfs_type="${2}"; shift 2 ;;
            -a) auto_kernel="${2}"; shift 2 ;;
            -s) 
                if [[ "${2}" =~ / ]]; then
                    boot_mb="${2%%/*}"
                    root_mb="${2##*/}"
                else
                    root_mb="${2}"
                fi
                shift 2 ;;
            -n) builder_name="${2}"; shift 2 ;;
            --) shift; break ;;
            *) error_msg "Unknown option ${1}";;
        esac
    done

    [[ ! -f "${model_conf}" ]] && error_msg "model_database.conf not found!"
}

# ────────────────────────────────────────────────────────────────────────────────
#  下载 Alpine minirootfs + 内核（复用原内核下载逻辑）
# ────────────────────────────────────────────────────────────────────────────────
download_alpine_rootfs() {
    process_msg "Downloading Alpine minirootfs..."
    mkdir -p "${tmp_dir}"
    wget -c -O "${tmp_dir}/${ALPINE_MINIROOTFS}" "${ALPINE_URL}" || error_msg "Download Alpine failed"
}

# ────────────────────────────────────────────────────────────────────────────────
#  核心：创建 rootfs（替换原 extract_armbian / refactor_rootfs）
# ────────────────────────────────────────────────────────────────────────────────
build_alpine_rootfs() {
    local rootfs_mount="${tmp_armbian}/rootfs"
    mkdir -p "${tmp_armbian}" "${rootfs_mount}"

    process_msg "Extracting Alpine minirootfs..."
    tar -xzf "${tmp_dir}/${ALPINE_MINIROOTFS}" -C "${rootfs_mount}"

    process_msg "Configuring Alpine (chroot)..."
    mount --bind /dev "${rootfs_mount}/dev"
    mount --bind /proc "${rootfs_mount}/proc"
    mount --bind /sys "${rootfs_mount}/sys"
    mount --bind /run "${rootfs_mount}/run"

    chroot "${rootfs_mount}" /bin/sh <<'EOF'
        apk update
        apk add --no-cache alpine-base bash sudo openssh-server linux-firmware \
                           e2fsprogs btrfs-progs dosfstools parted \
                           coreutils findutils grep sed gawk tar \
                           util-linux busybox-initscripts

        rc-update add sshd default
        rc-update add networking default
        rc-update add crond default
        rc-update add syslog boot

        echo "root:alpine" | chpasswd
        adduser -D -s /bin/ash user
        echo "user ALL=(ALL) ALL" >> /etc/sudoers

        ln -sf /usr/share/zoneinfo/UTC /etc/localtime
        echo "Alpine Linux ${ALPINE_VERSION} (custom for Amlogic)" > /etc/motd
        echo "Welcome to Alpine on Amlogic TV Box" > /etc/issue

        sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
EOF

    umount -l "${rootfs_mount}"/{dev,proc,sys,run} 2>/dev/null || true

    # 复制 Armbian 的 overlay 文件（保留 Armbian 的 armbian-install、fstab 模板等）
    cp -rf "${common_files}"/* "${rootfs_mount}"/
    cp -rf "${platform_files}"/amlogic/* "${rootfs_mount}"/ 2>/dev/null || true
    cp -rf "${different_files}"/* "${rootfs_mount}"/ 2>/dev/null || true

    process_msg "Alpine rootfs ready at ${rootfs_mount}"
}

# ────────────────────────────────────────────────────────────────────────────────
#  主流程（简化版，复用原内核/u-boot/boot 处理）
# ────────────────────────────────────────────────────────────────────────────────
main() {
    init_var "$@"
    download_alpine_rootfs

    # 这里假设你有原仓库的 download_kernel / check_kernel / replace_kernel 等函数
    # 如果没有，请从原 rebuild 复制过来，或手动下载内核到 ${kernel_path}
    # process_msg "Assuming kernel already prepared in ${kernel_path}"

    build_alpine_rootfs

    # 以下调用原逻辑（需原 rebuild 存在同目录，或复制函数）
    # extract_armbian → 跳过，已用 build_alpine_rootfs 替代
    # make_image / copy_files / refactor_bootfs / refactor_rootfs → 需要适配或复制原函数并修改
    # 建议：复制原 rebuild 的 refactor_bootfs / make_image / copy_files / clean_tmp 等函数到此脚本末尾
    # 并在 refactor_rootfs 处调用 build_alpine_rootfs 后的路径

    echo -e "${SUCCESS} Build finished. Check ${armbian_outputpath}"
    echo "Next step: manually integrate with original packing logic or extend this script."
}

main "$@"
