import Foundation

/// Builds the OTA install manifest plist iOS fetches via
/// `itms-services://?action=download-manifest&url=<this>`.
/// Native port of `ipa_sideload`'s `src/manifest.js`.
enum ManifestBuilder {
    static func manifest(ipaURL: String, bundleID: String, version: String, title: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>items</key>
          <array>
            <dict>
              <key>assets</key>
              <array>
                <dict>
                  <key>kind</key>
                  <string>software-package</string>
                  <key>url</key>
                  <string>\(esc(ipaURL))</string>
                </dict>
              </array>
              <key>metadata</key>
              <dict>
                <key>bundle-identifier</key>
                <string>\(esc(bundleID))</string>
                <key>bundle-version</key>
                <string>\(esc(version))</string>
                <key>kind</key>
                <string>software</string>
                <key>title</key>
                <string>\(esc(title))</string>
              </dict>
            </dict>
          </array>
        </dict>
        </plist>
        """
    }

    /// `itms-services://` link that hands `installd` the manifest URL.
    static func installLink(manifestURL: String) -> String {
        let encoded = manifestURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? manifestURL
        return "itms-services://?action=download-manifest&url=\(encoded)"
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
