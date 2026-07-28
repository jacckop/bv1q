#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL WGArabicLocalizationEnabled(void);
FOUNDATION_EXPORT NSString *WGArabicTranslateString(NSString *input);
FOUNDATION_EXPORT NSString *WGArabicTranslateStringExact(NSString *input);
FOUNDATION_EXPORT NSAttributedString *WGArabicTranslateAttributedString(NSAttributedString *input);
FOUNDATION_EXPORT NSAttributedString *WGArabicTranslateAttributedStringExact(NSAttributedString *input);

NS_ASSUME_NONNULL_END
