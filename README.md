# WhitegramArabic NodeFix v6.1

ديلب مستقل لتعريب قسم **Whitegram Features** وخياراته في Whitegram 12.9.2 (60)، ومخصص للحقن داخل ملف IPA ثم إعادة توقيعه. لا يعتمد على Substrate أو ElleKit.

## إصلاح البناء والتعريب في v6.1

الإصدار v5 أصلح تعليق صفحة إعدادات تيليجرام، لكنه اشترط وجود دالة Runtime خاصة باسم `object_setIvarWithStrongDefault` حتى يكتب النص العربي داخل عُقد Texture وSwift. هذه الدالة غير متوفرة في بعض إصدارات iOS، لذلك كان الديلب يجد النصوص لكنه يتركها إنكليزية بدون أي كرش.

الإصدار v6 كان يحتوي مساراً احتياطياً يستدعي `objc_storeStrong` عبر مؤشر `id *`. مترجم Apple يرفض هذا الأسلوب مع ARC، لذلك كان البناء يتوقف داخل `Sources/Tweak.m` قبل إنشاء الديلب.

v6.1 يحذف مسار المؤشر غير المتوافق مع ARC، ويستخدم `object_setIvarWithStrongDefault` عند توفره، ثم `object_setIvar` كمسار احتياطي متوافق مع البناء. يبقى نظام الفحص المدمج والمحدود السرعة كما هو لمنع كرش إعدادات تيليجرام.

## التغطية

- قاموس التعريب: **988** مدخلاً.
- النصوص المستخرجة من Whitegram 12.9.2: **593** نصاً.
- أخطاء المتغيرات مثل `%@` و`%d`: صفر.
- يتضمن نصوص الصور المرفقة مثل: Appearance، Liquid Glass، Ghost Mode، Always show me online وخيارات الإخفاء متعددة الأسطر.

## البناء عبر GitHub Actions

1. ارفع محتويات هذا المجلد إلى جذر مستودع GitHub.
2. افتح **Actions**.
3. اختر **Build Whitegram Arabic Dylib**.
4. اضغط **Run workflow**.
5. نزّل Artifact باسم `WhitegramArabic-NodeFix-v6.1`.

## الحقن الصحيح

استخدم IPA نظيفاً واحذف ديلب v4 أو v5 أو أي نسخة أقدم أولاً. لا تحقن v6.1 فوق تطبيق يحتوي نسخة قديمة من الديلب.

ضع الديلب داخل:

`Payload/Telegram.app/Frameworks/WhitegramArabic.dylib`

ثم أضف تحميله إلى Mach-O الرئيسي باسم:

`@rpath/WhitegramArabic.dylib`

يجب أن توجد إحالة تحميل واحدة فقط للديلب، ثم أعد توقيع التطبيق بالكامل.

## التوافق

- Whitegram: 12.9.2 (60)
- Bundle ID: `ph.telegra.Telegraph`
- المعمارية: arm64
- الحد الأدنى: iOS 15

## التحقق محلياً

```bash
python3 tools/verify_translations.py
python3 tools/generate_translations.py
```
