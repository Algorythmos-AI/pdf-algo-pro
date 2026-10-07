# StoreKit test data

`Products.storekit` is a StoreKit configuration for tests only (ADR-0026). It names the Pro
subscription's two products for the Debug bundle identifier, so `SKTestSession` can load, buy,
renew and expire them on the simulator without the App Store.

Its amounts and periods are test data. They say nothing about what the app costs or how long a
trial lasts: those are set in App Store Connect. The file belongs to the test target and is never
a resource of the app. The `PDFAlgoPro` scheme's Run action points to it, so the Debug app run
from Xcode shows the offer with these test plans; `scripts/ci/invariants.py` fails the build on a `.storekit` file anywhere
else.
