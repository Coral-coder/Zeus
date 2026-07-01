import Foundation

/// On-device UDID capture. iOS never lets an app read its own UDID (this is why
/// AltStore needs a computer). We get around it *without a cable*: Zeus serves a
/// tiny "Profile Service" enrollment profile the user installs once from Safari;
/// the device then POSTs a signed plist of its attributes (including UDID) back
/// to Zeus's loopback server. We read the UDID out of that response.
final class UDIDCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    var udid: String? {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}

enum EnrollmentProfile {
    /// A `Profile Service` .mobileconfig that makes the device POST its UDID to
    /// `postURL` on install.
    static func mobileconfig(postURL: String) -> String {
        let uuid = UUID().uuidString
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>PayloadContent</key>
          <dict>
            <key>URL</key><string>\(postURL)</string>
            <key>DeviceAttributes</key>
            <array>
              <string>UDID</string>
              <string>PRODUCT</string>
              <string>VERSION</string>
              <string>SERIAL</string>
            </array>
          </dict>
          <key>PayloadOrganization</key><string>Zeus</string>
          <key>PayloadDisplayName</key><string>Zeus device enrollment</string>
          <key>PayloadVersion</key><integer>1</integer>
          <key>PayloadUUID</key><string>\(uuid)</string>
          <key>PayloadIdentifier</key><string>com.lightwave.zeus.enroll</string>
          <key>PayloadType</key><string>Profile Service</string>
        </dict>
        </plist>
        """
    }
}

enum EnrollmentResponse {
    /// The device POSTs a PKCS#7-signed plist. The plist body is ASCII XML
    /// embedded in the DER, so we can pull the UDID straight out by pattern.
    static func parseUDID(from body: Data) -> String? {
        let text = String(decoding: body, as: UTF8.self)
        let pattern = "<key>UDID</key>\\s*<string>([^<]+)</string>"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
