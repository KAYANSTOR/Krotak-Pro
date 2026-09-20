#!/usr/bin/env sh
# تجهيز توقيع Release محليًا من أسرار يوفرها المطوّر عبر متغيرات البيئة.
#
# مطلوب:
#   APK_KEYSTORE_B64
#   APK_KEYSTORE_PASSWORD
#   APK_KEY_PASSWORD
#
# الاختياري:
#   APK_KEY_ALIAS (الافتراضي: net-upload)
#
# لا يضع هذا السكربت أي مفتاح خاص أو كلمة مرور داخل المستودع.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$root"

: "${APK_KEYSTORE_B64:?خطأ: عرّف APK_KEYSTORE_B64 في البيئة}"
: "${APK_KEYSTORE_PASSWORD:?خطأ: عرّف APK_KEYSTORE_PASSWORD في البيئة}"
: "${APK_KEY_PASSWORD:?خطأ: عرّف APK_KEY_PASSWORD في البيئة}"
APK_KEY_ALIAS="${APK_KEY_ALIAS:-net-upload}"

mkdir -p android/app/keystore

if printf '%s' "$APK_KEYSTORE_B64" | base64 -d > android/app/keystore/net-upload.jks 2>/dev/null; then
  :
else
  printf '%s' "$APK_KEYSTORE_B64" | base64 -D > android/app/keystore/net-upload.jks
fi

chmod 600 android/app/keystore/net-upload.jks

cat > android/key.properties <<EOF
storeFile=keystore/net-upload.jks
storeType=PKCS12
keyAlias=$APK_KEY_ALIAS
storePassword=$APK_KEYSTORE_PASSWORD
keyPassword=$APK_KEY_PASSWORD
EOF

chmod 600 android/key.properties

echo "تم تجهيز توقيع Release محليًا."
echo "يمكنك الآن تنفيذ: flutter build apk --release"
