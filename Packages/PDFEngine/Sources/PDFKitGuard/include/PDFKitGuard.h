#import <PDFKit/PDFKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The selection's attributed string, or nil when PDFKit has none or throws building it.
///
/// PDFKit raises an Objective-C exception, which Swift cannot catch, when it can't make a font for a
/// run of the text: it puts nil into a dictionary (#311). The exception is caught here, so the caller
/// falls back as it does when there is no attributed string, instead of the app ending.
NSAttributedString *_Nullable PAPGuardedAttributedString(PDFSelection *selection)
    NS_SWIFT_NAME(guardedAttributedString(of:));

NS_ASSUME_NONNULL_END
