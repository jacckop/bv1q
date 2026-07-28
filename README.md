# WhitegramArabic NodeFix v7

ديلب مستقل لتعريب قسم **Whitegram Features** وخياراته في Whitegram 12.9.2 (60)، ومخصص للحقن داخل ملف IPA ثم إعادة توقيعه. لا يعتمد على Substrate أو ElleKit.

## سبب اختفاء التعريب في v5 وv6.1

بالمقارنة مع المشروع الأصلي v3 ظهر اختلافان عطّلا مسار ظهور الترجمة:

1. المشروع الأصلي كان يعترض `NSBundle localizedStringForKey:value:table:` ويترجم النص قبل إنشاء عنصر الواجهة. هذا الاعتراض حُذف في v5 وبقي محذوفاً في v6.1، لذلك لم تعد أغلب نصوص Whitegram تصل إلى الواجهة باللغة العربية.
2. المسار الاحتياطي لعُقد Swift كان يشترط أن يبدأ `ivar_getTypeEncoding` بالحرف `@`. عُقدة `ComponentFlow.Text.MeasureState.attributedText` في Whitegram 12.9.2 تعرض ترميزاً فارغاً، لذلك كان الكود يرفض تعديلها دائماً رغم وجود الترجمة في القاموس.

v7 يعيد اعتراض `NSBundle` لكن بالمطابقة الكاملة فقط، ويسمح بالـSwift ivar المعروف عندما يكون ترميزه فارغاً. يبقى نظام الفحص مدمجاً ومحدود السرعة من v5 لمنع عودة تعليق إعدادات تيليجرام، ولا تتم إعادة اعتراض `UITextView` حتى لا يتغير نص الرسائل أو المحتوى القابل للتحرير.

## التغطية

- قاموس التعريب: **988** مدخلاً.
- النصوص المستخرجة من Whitegram 12.9.2: **593** نصاً.
- أخطاء المتغيرات مثل `%@` و`%d`: صفر.
- يتضمن نصوص Appearance وLiquid Glass وGhost Mode وخيارات Always show me وخيارات الإخفاء متعددة الأسطر.

## البناء عبر GitHub Actions

1. احذف ملفات الإصدار القديم من المستودع.
2. ارفع **محتويات** هذا المجلد إلى جذر المستودع، وليس المجلد نفسه.
3. افتح **Actions** واختر **Build Whitegram Arabic Dylib**.
4. اضغط **Run workflow**.
5. نزّل Artifact باسم `WhitegramArabic-NodeFix-v7`.

## الحقن الصحيح

استخدم IPA نظيفاً واحذف أي نسخة سابقة من `WhitegramArabic.dylib` وإحالة التحميل الخاصة بها قبل الحقن.

ضع الديلب داخل:

`Payload/Telegram.app/Frameworks/WhitegramArabic.dylib`

وأضف إلى Mach-O الرئيسي إحالة واحدة فقط:

`@rpath/WhitegramArabic.dylib`

ثم أعد توقيع التطبيق بالكامل.

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
