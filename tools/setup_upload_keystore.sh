#!/usr/bin/env sh
# يستخرج مفتاح التوقيع الثابت المُخزّن في المستودع إلى مكانه المحلي، حتى تُوقّع
# بناءاتك المحلية بنفس مفتاح بناءات CI — فيثبّت أي APK جديد فوق التطبيق المثبّت
# مباشرةً بدون رسالة «حزمة التثبيت لا تتوافق مع النسخة المثبّتة».
#
# الاستخدام:  sh ./tools/setup_upload_keystore.sh
#
# ثم:  flutter build apk --release
set -e

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

if [ ! -f android/signing/net-upload.jks.b64 ]; then
  echo "خطأ: لم يُعثر على android/signing/net-upload.jks.b64" >&2
  exit 1
fi

mkdir -p android/app/keystore

# GNU base64 يستخدم -d وmacOS يستخدم -D.
if base64 -d android/signing/net-upload.jks.b64 > android/app/keystore/net-upload.jks 2>/dev/null; then
  :
else
  base64 -D android/signing/net-upload.jks.b64 > android/app/keystore/net-upload.jks
fi

{
  echo "storeFile=keystore/net-upload.jks"
  echo "storeType=PKCS12"
  echo "keyAlias=net-upload"
  echo "storePassword=netupload2026"
  echo "keyPassword=netupload2026"
} > android/key.properties

echo "تم تجهيز مفتاح التوقيع الثابت:"
echo "  android/app/keystore/net-upload.jks"
echo "  android/key.properties"
echo "يمكنك الآن: flutter build apk --release"
