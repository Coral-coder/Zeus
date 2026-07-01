#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C++ wrapper around vendored zsign. Swift calls this to re-sign an
/// already-extracted `.app` payload folder in-process (no separate binary).
@interface ZsignBridge : NSObject

/// Re-sign the app bundle rooted at `folder` (the directory that contains
/// `Payload/<App>.app`) with the given signing identity.
///
/// - certPath: PEM/DER certificate file, or "" if `keyPath` is a .p12 that
///   already contains the certificate.
/// - keyPath: PEM/DER private key file, or a .p12 file.
/// - password: password for the .p12 / encrypted key, or "".
/// - provisionPath: the `.mobileprovision` to embed.
/// - bundleId: new bundle id to set, or nil to keep the app's own.
/// Returns YES on success; on failure returns NO and sets `error`.
+ (BOOL)signAppFolder:(NSString *)folder
             certPath:(NSString *)certPath
              keyPath:(NSString *)keyPath
             password:(NSString *)password
        provisionPath:(NSString *)provisionPath
             bundleId:(nullable NSString *)bundleId
                error:(NSString * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
