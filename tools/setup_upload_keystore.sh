#!/usr/bin/env sh
# يجهّز مفتاح توقيع Android محلياً من متغيرات البيئة فقط.
# لا تضع keystore أو كلمات المرور داخل المستودع.
#
# المتغيرات المطلوبة:
#   APK_KEYSTORE_B64
#   APK_KEYSTORE_PASSWORD
#   APK_KEY_PASSWORD
#   APK_KEY_ALIAS
#
# الاستخدام:
#   export APK_KEYSTORE_B64="$(base64 -w 0 /secure/path/upload.jks)"
#   export APK_KEYSTORE_PASSWORD='...'
#   export APK_KEY_PASSWORD='...'
#   export APK_KEY_ALIAS='...'
#   sh ./tools/setup_upload_keystore.sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$root"

: "${APK_KEYSTORE_B64:?خطأ: APK_KEYSTORE_B64 غير مضبوط}"
: "${APK_KEYSTORE_PASSWORD:?خطأ: APK_KEYSTORE_PASSWORD غير مضبوط}"
: "${APK_KEY_PASSWORD:?خطأ: APK_KEY_PASSWORD غير مضبوط}"
: "${APK_KEY_ALIAS:?خطأ: APK_KEY_ALIAS غير مضبوط}"

mkdir -p android/app/keystore

if printf '%s' "$APK_KEYSTORE_B64" | base64 -d > android/app/keystore/upload.jks 2>/dev/null; then
  :
elif printf '%s' "$APK_KEYSTORE_B64" | base64 -D > android/app/keystore/upload.jks 2>/dev/null; then
  :
else
  echo "خطأ: APK_KEYSTORE_B64 ليس Base64 صالحاً" >&2
  rm -f android/app/keystore/upload.jks
  exit 1
fi

umask 077
{
  printf 'storeFile=keystore/upload.jks\n'
  printf 'storeType=PKCS12\n'
  printf 'keyAlias=%s\n' "$APK_KEY_ALIAS"
  printf 'storePassword=%s\n' "$APK_KEYSTORE_PASSWORD"
  printf 'keyPassword=%s\n' "$APK_KEY_PASSWORD"
} > android/key.properties

echo "تم تجهيز مفتاح التوقيع من متغيرات البيئة فقط."
echo "شغّل flutter build apk --release ثم احذف android/key.properties و android/app/keystore/upload.jks."
trap 'rm -f android/key.properties android/app/keystore/upload.jks' EXIT INT TERM
flutter build apk --release
