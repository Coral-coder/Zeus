#import "ZsignBridge.h"

#include <string>
#include <vector>

#include "openssl.h"
#include "bundle.h"

@implementation ZsignBridge

+ (BOOL)signAppFolder:(NSString *)folder
             certPath:(NSString *)certPath
              keyPath:(NSString *)keyPath
             password:(NSString *)password
        provisionPath:(NSString *)provisionPath
             bundleId:(NSString *)bundleId
                error:(NSString * _Nullable * _Nullable)error {
    std::string cert = certPath.length ? certPath.UTF8String : "";
    std::string pkey = keyPath.length ? keyPath.UTF8String : "";
    std::string prov = provisionPath.length ? provisionPath.UTF8String : "";
    std::string pass = password.length ? password.UTF8String : "";

    ZSignAsset asset;
    if (!asset.Init(cert, pkey, prov, /*entitlements*/ "", pass,
                    /*adhoc*/ false, /*sha256Only*/ false, /*singleBinary*/ false)) {
        if (error) { *error = @"Could not load the signing identity (cert / key / profile)."; }
        return NO;
    }

    ZBundle bundle;
    std::vector<std::string> noDylibs;
    bool ok = bundle.SignFolder(&asset,
                                folder.UTF8String,
                                bundleId.length ? std::string(bundleId.UTF8String) : std::string(),
                                /*bundleVersion*/ "",
                                /*displayName*/ "",
                                noDylibs,
                                noDylibs,
                                /*force*/ true,
                                /*weakInject*/ false,
                                /*enableCache*/ false,
                                /*removeProvision*/ false);
    if (!ok && error) { *error = @"zsign failed to sign the app bundle."; }
    return ok ? YES : NO;
}

@end
