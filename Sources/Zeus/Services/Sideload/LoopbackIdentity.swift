import Foundation
import Security
import Network
import Crypto
import X509
import SwiftASN1

/// Mints and persists the TLS identity that lets Zeus host a local HTTPS server
/// iOS's install daemon will trust.
///
/// iOS's installd is stricter than Safari: it will not accept a CA certificate
/// used directly as the server (leaf) certificate. So we build a proper little
/// PKI:
///   • a self-signed **root CA** (this is what you trust via the profile), and
///   • a **leaf** server cert *signed by that root*, covering localhost /
///     127.0.0.1 with the serverAuth EKU — this is what the server presents.
/// The device trusts the root once; installd validates leaf → root → trusted.
enum LoopbackIdentity {
    // v2 = leaf-under-root scheme (v1 was a single CA-as-leaf cert).
    private static let leafKeyTag = "com.lightwave.zeus.sideload.leafkey.v2".data(using: .utf8)!
    private static let leafCertLabel = "Zeus Local Server"
    private static let rootCertLabel = "Zeus Local Root CA"
    // Old v1 keychain labels/tag, cleaned up on regeneration.
    private static let v1KeyTag = "com.lightwave.zeus.sideload.tlskey".data(using: .utf8)!
    private static let v1CertLabel = "Zeus Local Root"

    enum IdentityError: LocalizedError {
        case keyImport(OSStatus)
        case certCreate
        case identityLookup(OSStatus)
        case rootMissing
        case secIdentity

        var errorDescription: String? {
            switch self {
            case .keyImport(let s): return "Could not import the signing key (OSStatus \(s))."
            case .certCreate: return "Could not build the local certificate."
            case .identityLookup(let s): return "Could not read the TLS identity (OSStatus \(s))."
            case .rootMissing: return "Local root certificate not found."
            case .secIdentity: return "Could not create a TLS identity for the local server."
            }
        }
    }

    /// The leaf identity the server presents, plus the ROOT certificate DER
    /// (what the trust profile installs).
    struct Result {
        let identity: SecIdentity
        let certificateDER: Data   // the ROOT cert (for the trust profile)
    }

    static func ensure() throws -> Result {
        if let existing = try? load() { return existing }
        try generateAndStore()
        return try load()
    }

    static func secIdentity(from identity: SecIdentity) throws -> sec_identity_t {
        guard let sec = sec_identity_create(identity) else { throw IdentityError.secIdentity }
        return sec
    }

    // MARK: - Keychain lookup

    private static func load() throws -> Result {
        // The leaf identity (only identity we plant — the root has no private key).
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let ref = out else { throw IdentityError.identityLookup(status) }
        let identity = ref as! SecIdentity

        // The ROOT cert (kept in the keychain without a key) — for the profile.
        guard let rootDER = rootCertificateDER() else { throw IdentityError.rootMissing }
        return Result(identity: identity, certificateDER: rootDER)
    }

    private static func rootCertificateDER() -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: rootCertLabel,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let ref = out else { return nil }
        return SecCertificateCopyData(ref as! SecCertificate) as Data?
    }

    // MARK: - Generation

    private static func generateAndStore() throws {
        cleanup()

        let now = Date()
        let notBefore = now.addingTimeInterval(-3600)
        let notAfter = now.addingTimeInterval(60 * 60 * 24 * 3650)

        // 1. Root CA (self-signed). Its private key is used only to sign the leaf
        //    and is then discarded — the root lives on as a trusted anchor.
        let rootKey = P256.Signing.PrivateKey()
        let rootCertKey = Certificate.PrivateKey(rootKey)
        let rootName = try DistinguishedName { CommonName("Zeus Local Root") }
        let rootCert = try Certificate(
            version: .v3,
            serialNumber: randomSerial(),
            publicKey: rootCertKey.publicKey,
            notValidBefore: notBefore, notValidAfter: notAfter,
            issuer: rootName, subject: rootName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
                Critical(KeyUsage(digitalSignature: true, keyCertSign: true))
            },
            issuerPrivateKey: rootCertKey
        )
        let rootDER = Data(try rootCert.serializeAsPEM().derBytes)

        // 2. Leaf server cert, SIGNED BY THE ROOT, covering localhost/127.0.0.1.
        let leafKey = P256.Signing.PrivateKey()
        let leafCertKey = Certificate.PrivateKey(leafKey)
        let leafName = try DistinguishedName { CommonName("Zeus Local Server") }
        let leafCert = try Certificate(
            version: .v3,
            serialNumber: randomSerial(),
            publicKey: leafCertKey.publicKey,
            notValidBefore: notBefore, notValidAfter: notAfter,
            issuer: rootName, subject: leafName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                KeyUsage(digitalSignature: true)
                try ExtendedKeyUsage([.serverAuth])
                SubjectAlternativeNames([
                    .dnsName("localhost"),
                    .ipAddress(ASN1OctetString(contentBytes: ArraySlice<UInt8>([127, 0, 0, 1])))
                ])
            },
            issuerPrivateKey: rootCertKey   // ← issued by the root
        )
        let leafDER = Data(try leafCert.serializeAsPEM().derBytes)

        // 3. Import the LEAF key + LEAF cert → forms the leaf SecIdentity.
        let secLeafKey = try importPrivateKey(leafKey)
        let addKey: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: leafKeyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecValueRef as String: secLeafKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let ks = SecItemAdd(addKey as CFDictionary, nil)
        guard ks == errSecSuccess || ks == errSecDuplicateItem else { throw IdentityError.keyImport(ks) }

        guard let secLeafCert = SecCertificateCreateWithData(nil, leafDER as CFData) else {
            throw IdentityError.certCreate
        }
        let cl = SecItemAdd([
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: secLeafCert,
            kSecAttrLabel as String: leafCertLabel
        ] as CFDictionary, nil)
        guard cl == errSecSuccess || cl == errSecDuplicateItem else { throw IdentityError.certCreate }

        // 4. Store the ROOT cert (no key) so we can build the trust profile.
        guard let secRootCert = SecCertificateCreateWithData(nil, rootDER as CFData) else {
            throw IdentityError.certCreate
        }
        let cr = SecItemAdd([
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: secRootCert,
            kSecAttrLabel as String: rootCertLabel
        ] as CFDictionary, nil)
        guard cr == errSecSuccess || cr == errSecDuplicateItem else { throw IdentityError.certCreate }
    }

    /// Remove any prior sideload keychain items (v1 single-cert scheme and any
    /// partial v2) so regeneration is clean.
    private static func cleanup() {
        for tag in [leafKeyTag, v1KeyTag] {
            SecItemDelete([kSecClass as String: kSecClassKey,
                           kSecAttrApplicationTag as String: tag] as CFDictionary)
        }
        for label in [leafCertLabel, rootCertLabel, v1CertLabel] {
            SecItemDelete([kSecClass as String: kSecClassCertificate,
                           kSecAttrLabel as String: label] as CFDictionary)
        }
    }

    private static func randomSerial() -> Certificate.SerialNumber {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Certificate.SerialNumber(bytes: bytes)
    }

    private static func importPrivateKey(_ key: P256.Signing.PrivateKey) throws -> SecKey {
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(key.x963Representation as CFData, attrs as CFDictionary, &error) else {
            throw IdentityError.keyImport(errSecParam)
        }
        return secKey
    }
}
