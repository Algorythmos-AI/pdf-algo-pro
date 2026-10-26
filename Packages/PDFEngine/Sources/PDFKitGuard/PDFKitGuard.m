#import "PDFKitGuard.h"

NSAttributedString *_Nullable PAPGuardedAttributedString(PDFSelection *selection) {
  @try {
    return selection.attributedString;
  } @catch (NSException *exception) {
    return nil;
  }
}
