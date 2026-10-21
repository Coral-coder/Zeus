import Foundation

/// Builds the unsigned `.mobileconfig` that installs Zeus's local certificate as
/// a trusted root, so on-device OTA installs over the loopback HTTPS server work.
/// Native port of `ipa_sideload`'s `trustProfile()` in `src/tls.js`.
///
/// iOS marks this "Not Verified" on install (expected for a self-signed root);
/// the user finishes by enabling it under Settings → General → About →
/// Certificate Trust Settings.
enum TrustProfileBuilder {
    static func mobileconfig(certificateDER: Data) -> String {
        let der = certificateDER.base64EncodedString()
        let rootUUID = UUID().uuidString
        let configUUID = UUID().uuidString
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>PayloadContent</key>
          <array>
            <dict>
              <key>PayloadType</key><string>com.apple.security.root</string>
              <key>PayloadVersion</key><integer>1</integer>
              <key>PayloadIdentifier</key><string>com.lightwave.zeus.sideload.root</string>
              <key>PayloadUUID</key><string>\(rootUUID)</string>
              <key>PayloadDisplayName</key><string>Zeus local root</string>
              <key>PayloadCertificateFileName</key><string>zeus-local.cer</string>
              <key>PayloadContent</key>
              <data>\(der)</data>
            </dict>
          </array>
          <key>PayloadType</key><string>Configuration</string>
          <key>PayloadVersion</key><integer>1</integer>
          <key>PayloadIdentifier</key><string>com.lightwave.zeus.sideload.trust</string>
          <key>PayloadUUID</key><string>\(configUUID)</string>
          <key>PayloadDisplayName</key><string>Zeus sideload trust</string>
          <key>PayloadDescription</key><string>Trusts Zeus's local server so on-device app installs work.</string>
        </dict>
        </plist>
        """
    }
}
