#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# InstallerX Revived - AOSP Magisk Module Builder
# Patches package name to 'com.android.packageinstaller' and builds AOSP.zip.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_DIR="${ROOT_DIR}/template"
DIST_DIR="${ROOT_DIR}/dist"
TOOLS_DIR="${ROOT_DIR}/tools"
mkdir -p "${DIST_DIR}" "${TOOLS_DIR}"

UPSTREAM_REPO="wxxsfxyzm/InstallerX-Revived"
APP_ID="com.android.packageinstaller"
TARGET_TAG="${1:-}"

echo "========================================================"
echo " InstallerX Revived - AOSP Magisk Module Builder"
echo " Target Package: ${APP_ID}"
echo "========================================================"

# 1. Detect Android Build Tools
ANDROID_SDK=""
if [ -n "${ANDROID_HOME:-}" ] && [ -d "${ANDROID_HOME}" ]; then
    ANDROID_SDK="${ANDROID_HOME}"
elif [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "${ANDROID_SDK_ROOT}" ]; then
    ANDROID_SDK="${ANDROID_SDK_ROOT}"
elif [ -d "${HOME}/Android/Sdk" ]; then
    ANDROID_SDK="${HOME}/Android/Sdk"
fi

BUILD_TOOLS_DIR=""
if [ -n "${ANDROID_SDK}" ] && [ -d "${ANDROID_SDK}/build-tools" ]; then
    for bt in $(ls -vd "${ANDROID_SDK}/build-tools/"*/ 2>/dev/null | tac); do
        if [ -f "${bt}aapt2" ] && [ -f "${bt}zipalign" ] && [ -f "${bt}apksigner" ]; then
            BUILD_TOOLS_DIR="${bt%/}"
            break
        fi
    done
fi

if [ -n "${BUILD_TOOLS_DIR}" ]; then
    AAPT2="${BUILD_TOOLS_DIR}/aapt2"
    ZIPALIGN="${BUILD_TOOLS_DIR}/zipalign"
    APKSIGNER="${BUILD_TOOLS_DIR}/apksigner"
else
    AAPT2="$(which aapt2 2>/dev/null || true)"
    ZIPALIGN="$(which zipalign 2>/dev/null || true)"
    APKSIGNER="$(which apksigner 2>/dev/null || true)"
fi

if [ -z "${AAPT2}" ] || [ -z "${ZIPALIGN}" ] || [ -z "${APKSIGNER}" ]; then
    echo "[-] Error: aapt2, zipalign or apksigner not found in PATH or Android SDK!" >&2
    exit 1
fi

echo "[+] aapt2:     ${AAPT2}"
echo "[+] zipalign:  ${ZIPALIGN}"
echo "[+] apksigner: ${APKSIGNER}"

# 2. Check Java
if ! command -v java >/dev/null 2>&1; then
    echo "[-] Error: Java runtime not found!" >&2
    exit 1
fi
echo "[+] Java:      $(java -version 2>&1 | head -n 1)"

# 3. Setup Apktool
APKTOOL_JAR="${TOOLS_DIR}/apktool.jar"
if [ ! -f "${APKTOOL_JAR}" ]; then
    echo "[+] Downloading Apktool v3.0.3..."
    curl -sL -o "${APKTOOL_JAR}" "https://github.com/iBotPeaches/Apktool/releases/download/v3.0.3/apktool_3.0.3.jar"
fi

# 4. Resolve Target Upstream Release
if [ -z "${TARGET_TAG}" ]; then
    echo "[+] Querying latest release from ${UPSTREAM_REPO}..."
    TARGET_TAG=$(curl -sL "https://api.github.com/repos/${UPSTREAM_REPO}/releases" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    for rel in data:
        for asset in rel.get("assets", []):
            name = asset.get("name", "")
            if name.endswith(".apk") and "online" in name:
                print(rel.get("tag_name", ""))
                sys.exit(0)
except Exception:
    pass
')
fi

if [ -z "${TARGET_TAG}" ]; then
    echo "[-] Error: Unable to determine target upstream release tag!" >&2
    exit 1
fi

echo "[+] Target Release Tag: ${TARGET_TAG}"

# 5. Fetch Download URL
DOWNLOAD_INFO=$(curl -sL "https://api.github.com/repos/${UPSTREAM_REPO}/releases/tags/${TARGET_TAG}" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    for asset in data.get("assets", []):
        name = asset.get("name", "")
        if name.endswith(".apk") and "online" in name:
            url = asset.get("browser_download_url")
            print(f"{url}|{name}")
            sys.exit(0)
except Exception:
    pass
')

if [ -z "${DOWNLOAD_INFO}" ]; then
    echo "[-] Error: Could not find online APK asset for tag ${TARGET_TAG}!" >&2
    exit 1
fi

IFS='|' read -r DOWNLOAD_URL APK_FILENAME <<< "${DOWNLOAD_INFO}"
echo "[+] APK Asset:   ${APK_FILENAME}"
echo "[+] Download URL: ${DOWNLOAD_URL}"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "${TEMP_DIR}"' EXIT

RAW_APK="${TEMP_DIR}/${APK_FILENAME}"
echo "[+] Downloading official upstream APK..."
curl -sL -o "${RAW_APK}" "${DOWNLOAD_URL}"

# 6. Setup Signing Keystore
KEYSTORE_FILE="${TEMP_DIR}/signing.jks"
if [ -n "${KEYSTORE_BASE64:-}" ]; then
    echo "[+] Using Keystore decoded from KEYSTORE_BASE64 secret..."
    echo "${KEYSTORE_BASE64}" | base64 --decode > "${KEYSTORE_FILE}"
elif [ -f "${ROOT_DIR}/installerx.jks" ]; then
    echo "[+] Using local installerx.jks..."
    cp -f "${ROOT_DIR}/installerx.jks" "${KEYSTORE_FILE}"
else
    echo "[+] Generating a temporary keystore for this build..."
    keytool -genkeypair -v -keystore "${KEYSTORE_FILE}" \
        -alias installerx -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass 123456 -keypass 123456 \
        -dname "CN=InstallerX, OU=AOSP, O=Android, C=US"
fi

# 7. Patch Package Name using Apktool
DECOMPILE_DIR="${TEMP_DIR}/decompiled"
echo "[+] Decompiling APK..."
java -jar "${APKTOOL_JAR}" d "${RAW_APK}" -o "${DECOMPILE_DIR}" -f >/dev/null

echo "[+] Patching package name to ${APP_ID}..."
python3 - << EOF
import os

root_dir = "${DECOMPILE_DIR}"
old_pkg = "com.rosan.installer.x.revived"
new_pkg = "${APP_ID}"

count = 0
for dirpath, dirnames, filenames in os.walk(root_dir):
    for f in filenames:
        if f.endswith(('.smali', '.xml', '.yml', '.properties')):
            p = os.path.join(dirpath, f)
            with open(p, 'rb') as fp:
                content = fp.read()
            if old_pkg.encode('utf-8') in content:
                new_content = content.replace(old_pkg.encode('utf-8'), new_pkg.encode('utf-8'))
                with open(p, 'wb') as fp:
                    fp.write(new_content)
                count += 1
print(f"    Patched references in {count} files.")
EOF

REBUILT_APK="${TEMP_DIR}/rebuilt.apk"
LOCAL_AAPT2="${TEMP_DIR}/aapt2"
cp -f "${AAPT2}" "${LOCAL_AAPT2}"
chmod +x "${LOCAL_AAPT2}"

echo "[+] Rebuilding APK with aapt2..."
java -jar "${APKTOOL_JAR}" b "${DECOMPILE_DIR}" -o "${REBUILT_APK}" --aapt "${LOCAL_AAPT2}" >/dev/null

ALIGNED_APK="${TEMP_DIR}/aligned.apk"
echo "[+] Aligning APK..."
"${ZIPALIGN}" -f -p 4 "${REBUILT_APK}" "${ALIGNED_APK}"

echo "[+] Signing APK (V2 + V3)..."
"${APKSIGNER}" sign --ks "${KEYSTORE_FILE}" \
    --ks-pass pass:123456 --ks-key-alias installerx --key-pass pass:123456 \
    --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
    "${ALIGNED_APK}"

"${APKSIGNER}" verify "${ALIGNED_APK}" >/dev/null

# 8. Package Final Artifacts
STANDALONE_APK="${DIST_DIR}/InstallerX-Revived-online-${TARGET_TAG}.apk"
cp -f "${ALIGNED_APK}" "${STANDALONE_APK}"
echo "[+] Patched APK created: ${STANDALONE_APK}"

STAGE_DIR="${TEMP_DIR}/module_stage"
mkdir -p "${STAGE_DIR}"
if [ -d "${TEMPLATE_DIR}" ]; then
    cp -r "${TEMPLATE_DIR}/." "${STAGE_DIR}/"
fi

mkdir -p "${STAGE_DIR}/system/priv-app/PackageInstaller"
cp -f "${ALIGNED_APK}" "${STAGE_DIR}/system/priv-app/PackageInstaller/PackageInstaller.apk"

# Update module.prop
CLEAN_VER="${TARGET_TAG}"
NUM_CODE=$(echo "${CLEAN_VER}" | tr -cd '0-9')
if [ ${#NUM_CODE} -lt 6 ]; then
    NUM_CODE="${NUM_CODE}00"
fi
NUM_CODE="${NUM_CODE:0:6}"

cat << EOF > "${STAGE_DIR}/module.prop"
id=com.android.packageinstaller
name=InstallerX Revived
version=${TARGET_TAG}
versionCode=${NUM_CODE}
author=wxxsfxyzm
description=InstallerX as System Package Installer (AOSP)
actionIcon=launcher.png
EOF

if [ -f "${STAGE_DIR}/action.sh" ]; then
    cat << 'EOF' > "${STAGE_DIR}/action.sh"
#!/system/bin/sh
am start -n com.android.packageinstaller/com.rosan.installer.ui.activity.SettingsActivity
EOF
fi

if [ -f "${STAGE_DIR}/uninstall.sh" ]; then
    cat << 'EOF' > "${STAGE_DIR}/uninstall.sh"
pm clear --user 0 com.android.packageinstaller
rm -r /data/system/package_cache/*
EOF
fi

for sh_file in action.sh customize.sh service.sh uninstall.sh module.prop; do
    if [ -f "${STAGE_DIR}/${sh_file}" ]; then
        sed -i 's/\r$//' "${STAGE_DIR}/${sh_file}"
        if [[ "${sh_file}" == *.sh ]]; then
            chmod 755 "${STAGE_DIR}/${sh_file}"
        else
            chmod 644 "${STAGE_DIR}/${sh_file}"
        fi
    fi
done

MODULE_ZIP="${DIST_DIR}/AOSP.zip"
rm -f "${MODULE_ZIP}"

python3 - << EOF
import os, zipfile

stage_dir = "${STAGE_DIR}"
zip_path = "${MODULE_ZIP}"

with zipfile.ZipFile(zip_path, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(stage_dir):
        for d in dirs:
            dir_path = os.path.join(root, d)
            arcname = os.path.relpath(dir_path, stage_dir) + '/'
            zinfo = zipfile.ZipInfo(arcname)
            zinfo.external_attr = 0o755 << 16 | 0x10
            z.writestr(zinfo, '')
        for file in files:
            file_path = os.path.join(root, file)
            arcname = os.path.relpath(file_path, stage_dir)
            z.write(file_path, arcname)
EOF

echo "[+] Flashable Module created: ${MODULE_ZIP}"

# 9. Output variables for GitHub Actions
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "tag=${TARGET_TAG}" >> "${GITHUB_OUTPUT}"
    echo "module_zip=${MODULE_ZIP}" >> "${GITHUB_OUTPUT}"
    echo "standalone_apk=${STANDALONE_APK}" >> "${GITHUB_OUTPUT}"
    echo "version_name=${TARGET_TAG}" >> "${GITHUB_OUTPUT}"
fi

echo "========================================================"
echo " Build Completed Successfully!"
echo " Module ZIP:     ${MODULE_ZIP}"
echo " Standalone APK: ${STANDALONE_APK}"
echo " Version:        ${TARGET_TAG}"
echo "========================================================"
