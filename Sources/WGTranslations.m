#import "WGTranslations.h"
#include "GeneratedTranslations.inc"

static NSDictionary<NSString *, NSString *> *WGTranslationTable(void) {
    static NSDictionary<NSString *, NSString *> *table;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        table = WGGeneratedTranslations();
    });
    return table;
}

static NSDictionary<NSString *, NSString *> *WGLowercaseTranslationTable(void) {
    static NSDictionary<NSString *, NSString *> *table;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary<NSString *, NSString *> *result = [NSMutableDictionary dictionary];
        [WGTranslationTable() enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
            (void)stop;
            NSString *lower = key.lowercaseString;
            if (!result[lower]) {
                result[lower] = value;
            }
        }];
        table = [result copy];
    });
    return table;
}

BOOL WGArabicLocalizationEnabled(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id explicitValue = [defaults objectForKey:@"WGArabicLocalizationEnabled"];
    if (explicitValue != nil) {
        return [explicitValue boolValue];
    }
    return YES;
}

static NSString *WGApplyRegexRules(NSString *input) {
    static NSArray<NSDictionary<NSString *, id> *> *rules;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSArray<NSString *> *> *rawRules = @[
            @[@"^Account \\\"(.+)\\\" is already added\\.$", @"الحساب «$1» مضاف مسبقاً."],
            @[@"^Restored accounts: ([0-9]+)$", @"الحسابات المستعادة: $1"],
            @[@"^([0-9]+) account\\(s\\) saved to Keychain$", @"تم حفظ $1 حساب في سلسلة المفاتيح"],
            @[@"^([0-9]+) messages will be restored and visible in the chat again\\.$", @"ستُستعاد $1 رسالة وتظهر مجدداً في المحادثة."],
            @[@"^Font changed: (.+)\\. Restart Whitegram$", @"تم تغيير الخط إلى $1. أعد تشغيل وايت كرام"],
            @[@"^Font selected: (.+)\\. Restart Whitegram$", @"تم اختيار الخط $1. أعد تشغيل وايت كرام"],
            @[@"^Restored ([0-9]+) messages \\(([0-9]+) new\\)\\.$", @"تمت استعادة $1 رسالة ($2 جديدة)."],
            @[@"^Restored ([0-9]+) settings\\. Restart Whitegram$", @"تمت استعادة $1 إعداد. أعد تشغيل وايت كرام"],
            @[@"^Downloading ([0-9]+)%$", @"جارٍ التنزيل $1٪"],
            @[@"^([0-9]+) of ([0-9]+) engines$", @"$1 من أصل $2 محرّك"],
            @[@"^Objects found: ([0-9]+)$", @"العناصر المكتشفة: $1"],
            @[@"^Done: ([0-9]+) messages$", @"تم: $1 رسالة"],
            @[@"^Total messages: ([0-9]+)$", @"إجمالي الرسائل: $1"],
            @[@"^Wallpaper add error: code ([0-9]+)$", @"خطأ في إضافة الخلفية: الرمز $1"],
            @[@"^Restored ([0-9]+) msg\\. from backup\\.$", @"تمت استعادة $1 رسالة من النسخة الاحتياطية."],
            @[@"^Showing lyrics for (.+)$", @"عرض كلمات $1"],
            @[@"^Network error: (.+)$", @"خطأ في الشبكة: $1"],
            @[@"^Selected: (.+)$", @"المحدد: $1"],
            @[@"^Show ([0-9]+) more$", @"إظهار $1 إضافية"],
            @[@"^([0-9]+) / 8 lines$", @"$1 / 8 أسطر"],
            @[@"^([0-9]+) msg\\.$", @"$1 رسالة"],
            @[@"^Restore \\\"(.+)\\\"\\?$", @"استعادة «$1»؟"],
            @[@"^No response from the model\\.$", @"لم يردّ النموذج."],
        ];

        NSMutableArray<NSDictionary<NSString *, id> *> *compiled = [NSMutableArray arrayWithCapacity:rawRules.count];
        for (NSArray<NSString *> *rawRule in rawRules) {
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:rawRule[0]
                                                                                  options:0
                                                                                    error:nil];
            if (regex) {
                [compiled addObject:@{@"regex": regex, @"replacement": rawRule[1]}];
            }
        }
        rules = [compiled copy];
    });

    NSRange fullRange = NSMakeRange(0, input.length);
    for (NSDictionary<NSString *, id> *rule in rules) {
        NSRegularExpression *regex = rule[@"regex"];
        NSString *replacement = rule[@"replacement"];
        if ([regex firstMatchInString:input options:0 range:fullRange]) {
            return [regex stringByReplacingMatchesInString:input
                                                   options:0
                                                     range:fullRange
                                              withTemplate:replacement];
        }
    }
    return input;
}

static NSString *WGTranslateCore(NSString *core, BOOL allowRegex) {
    NSString *translated = WGTranslationTable()[core];
    if (!translated) {
        translated = WGLowercaseTranslationTable()[core.lowercaseString];
    }

    if (!translated && core.length > 1) {
        unichar last = [core characterAtIndex:core.length - 1];
        if (last == ':' || last == '?' || last == '!' || last == '.') {
            NSString *base = [core substringToIndex:core.length - 1];
            NSString *baseTranslation = WGTranslationTable()[base];
            if (baseTranslation) {
                NSString *punctuation = [core substringFromIndex:core.length - 1];
                translated = [baseTranslation stringByAppendingString:punctuation];
            }
        }
    }

    if (!translated && allowRegex) {
        translated = WGApplyRegexRules(core);
    }
    return translated ?: core;
}

static NSString *WGTranslateStringInternal(NSString *input, BOOL allowRegex) {
    if (!WGArabicLocalizationEnabled() || input.length == 0 || input.length > 16384) {
        return input;
    }

    NSCharacterSet *trimSet = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSUInteger start = 0;
    while (start < input.length && [trimSet characterIsMember:[input characterAtIndex:start]]) {
        start++;
    }

    NSUInteger end = input.length;
    while (end > start && [trimSet characterIsMember:[input characterAtIndex:end - 1]]) {
        end--;
    }

    NSString *prefix = [input substringToIndex:start];
    NSString *core = [input substringWithRange:NSMakeRange(start, end - start)];
    NSString *suffix = [input substringFromIndex:end];
    NSString *translated = WGTranslateCore(core, allowRegex);

    if ([translated isEqualToString:core]) {
        return input;
    }
    return [NSString stringWithFormat:@"%@%@%@", prefix, translated, suffix];
}

NSString *WGArabicTranslateString(NSString *input) {
    return WGTranslateStringInternal(input, YES);
}

NSString *WGArabicTranslateStringExact(NSString *input) {
    return WGTranslateStringInternal(input, NO);
}

static NSAttributedString *WGTranslateAttributedStringInternal(NSAttributedString *input, BOOL exactOnly) {
    if (!WGArabicLocalizationEnabled() || input.length == 0 || input.length > 4096) {
        return input;
    }

    NSString *translated = exactOnly ? WGArabicTranslateStringExact(input.string)
                                     : WGArabicTranslateString(input.string);
    if ([translated isEqualToString:input.string]) {
        return input;
    }

    __block NSDictionary<NSAttributedStringKey, id> *uniformAttributes = nil;
    __block BOOL hasDifferentRuns = NO;
    [input enumerateAttributesInRange:NSMakeRange(0, input.length)
                              options:0
                           usingBlock:^(NSDictionary<NSAttributedStringKey, id> *attrs, NSRange range, BOOL *stop) {
        (void)range;
        if (!uniformAttributes) {
            uniformAttributes = attrs ?: @{};
        } else if (![uniformAttributes isEqualToDictionary:attrs ?: @{}]) {
            hasDifferentRuns = YES;
            *stop = YES;
        }
    }];

    // Rich attributed strings can contain entities, links or attachments whose
    // ranges must not be rewritten by a localization tweak.
    if (hasDifferentRuns) {
        return input;
    }

    return [[NSAttributedString alloc] initWithString:translated
                                           attributes:uniformAttributes ?: @{}];
}

NSAttributedString *WGArabicTranslateAttributedString(NSAttributedString *input) {
    return WGTranslateAttributedStringInternal(input, NO);
}

NSAttributedString *WGArabicTranslateAttributedStringExact(NSAttributedString *input) {
    return WGTranslateAttributedStringInternal(input, YES);
}
