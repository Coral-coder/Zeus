import Foundation
import Security
import Network
import Crypto
import X509
import SwiftASN1

/// Mints and persists the self-signed TLS identity that lets Zeus host a local
/// HTTPS server iOS's install daemon can trust.
///
/// This is the native equivalent of `ipa_sideload`'s `src/tls.js`: a long-lived
/// self-signed **CA** certificate (so it can be installed as a trusted root via
/// a configuration profile) covering `localhost` / `127.0.0.1`.
///
/// The tricky part on iOS is turning a cert + private key into a `SecIdentity`
/// usable by Network.framework:
///   1. Generate a P-256 keypair with swift-crypto (in memory).
///   2. Build + self-sign the X.509 CA cert over that key with swift-certificates.
///   3. Import the private key AND the certificate into the keychain.
///   4. The keychain automatically pairs them into a `SecIdentity`, which we
///      fetch with a `kSecClassIdentity` query and wrap as a `sec_identity_t`.
/// Everything persists, so trusting the root once is enough across launches.
enum LoopbackIdentity {
    private static let service = "com.lightwave.zeus.sideload"
    private static let keyTag = "com.lightwave.zeus.sideload.tlskey".data(using: .utf8)!
    private static let certLabel = "Zeus Local Root"

    enum IdentityError: LocalizedError {
        case keyImport(OSStatus)
        case certCreate
        case identityLookup(OSStatus)
        case secIdentity

        var errorDescription: String? {
            switch self {
            case .keyImport(let s): return "Could not import the signing key (OSStatus \(s))."
            case .certCreate: return "Could not build the local certificate."
            case .identityLookup(let s): return "Could not read the TLS identity (OSStatus \(s))."
            case .secIdentity: return "Could not create a TLS identity for the local server."
            }
        }
    }

    /// The identity plus the certificate DER (needed to build the trust profile).
    struct Result {
        let identity: SecIdentity
        let certificateDER: Data
    }

    /// Return the existing identity, or create + persist a fresh one.
    static func ensure() throws -> Result {
        if let existing = try? load() { return existing }
        try generateAndStore()
        return try load()
    }

    /// A `sec_identity_t` for NWListener TLS options.
    static func secIdentity(from identity: SecIdentity) throws -> sec_identity_t {
        guard let sec = sec_identity_create(identity) else { throw IdentityError.secIdentity }
        return sec
    }

    // MARK: - Keychain lookup

    private static func load() throws -> Result {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            // Zeus holds no other identities, so match the single one we planted.
            kSecAttrApplicationLabel as String: keyTag
        ]
        var out: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &out)
        if status != errSecSuccess {
            // Fall back to an unconstrained identity lookup (some iOS versions
            // don't index identities by the key's application label).
            var loose = query
            loose.removeValue(forKey: kSecAttrApplicationLabel as String)
            status = SecItemCopyMatching(loose as CFDictionary, &out)
        }
        guard status == errSecSuccess, let ref = out else {
            throw IdentityError.identityLookup(status)
        }
        let identity = ref as! SecIdentity

        var cert: SecCertificate?
        let cs = SecIdentityCopyCertificate(identity, &cert)
        guard cs == errSecSuccess, let cert, let der = SecCertificateCopyData(cert) as Data? else {
            throw IdentityError.identityLookup(cs)
        }
        return Result(identity: identity, certificateDER: der)
    }

    // MARK: - Generation

    private static func generateAndStore() throws {
        // 1. Keypair (swift-crypto, in memory).
        let privateKey = P256.Signing.PrivateKey()
        let certKey = Certificate.PrivateKey(privateKey)

        // 2. Self-signed CA cert covering localhost + 127.0.0.1.
        let name = try DistinguishedName { CommonName(certLabel) }
        let now = Date()
        var serial = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial)

        let cert = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(bytes: serial),
            publicKey: certKey.publicKey,
            notValidBefore: now.addingTimeInterval(-3600),
            notValidAfter: now.addingTimeInterval(60 * 60 * 24 * 3650),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
                Critical(KeyUsage(digitalSignature: true, keyCertSign: true))
                try ExtendedKeyUsage([.serverAuth])
                SubjectAlternativeNames([
                    .dnsName("localhost"),
                    .ipAddress(ASN1OctetString(contentBytes: ArraySlice<UInt8>([127, 0, 0, 1])))
                ])
            },
            issuerPrivateKey: certKey
        )

        let der = Data(try cert.serializeAsPEM().derBytes)

        // 3a. Import the private key into the keychain (kSecClassKey), tagged so
        //     we can find it and so it pairs with the cert into an identity.
        let secKey = try importPrivateKey(privateKey)
        let addKey: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecValueRef as String: secKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(addKey as CFDictionary)
        let ks = SecItemAdd(addKey as CFDictionary, nil)
        guard ks == errSecSuccess || ks == errSecDuplicateItem else { throw IdentityError.keyImport(ks) }

        // 3b. Import the certificate (kSecClassCertificate).
        guard let secCert = SecCertificateCreateWithData(nil, der as CFData) else {
            throw IdentityError.certCreate
        }
        let addCert: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: secCert,
            kSecAttrLabel as String: certLabel
        ]
        SecItemDelete([
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: certLabel
        ] as CFDictionary)
        let cs = SecItemAdd(addCert as CFDictionary, nil)
        guard cs == errSecSuccess || cs == errSecDuplicateItem else { throw IdentityError.certCreate }
    }

    /// Turn a swift-crypto P-256 private key into a keychain-importable `SecKey`
    /// via its X9.63 representation (0x04 || X || Y || private scalar).
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
