import Foundation
import Security

/// Generates an RSA-2048 keypair and a PKCS#10 Certificate Signing Request, the
/// way Xcode/`openssl req` do. The App Store Connect API issues a development
/// certificate from this CSR while the private key stays on-device — which is
/// exactly what lets Zeus sign apps without importing anything.
///
/// The DER is built by hand (small, deterministic TLV) to avoid depending on an
/// ASN.1 CSR API. Apple's iOS development certificates are RSA-2048.
enum CSR {
    struct Result {
        let privateKeyPEM: String   // PKCS#1 RSA private key (PEM) — kept locally
        let csrPEM: String          // PKCS#10 request (PEM) — sent to Apple
    }

    enum CSRError: LocalizedError {
        case keygen(String)
        case export(String)
        case sign(String)
        var errorDescription: String? {
            switch self {
            case .keygen(let m): return "Key generation failed: \(m)"
            case .export(let m): return "Key export failed: \(m)"
            case .sign(let m): return "CSR signing failed: \(m)"
            }
        }
    }

    static func generate(commonName: String, emailAddress: String) throws -> Result {
        // 1. RSA-2048 keypair (in memory; not stored in the keychain).
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
            throw CSRError.keygen(cfError(error))
        }
        guard let pub = SecKeyCopyPublicKey(priv) else { throw CSRError.keygen("no public key") }
        guard let pubData = SecKeyCopyExternalRepresentation(pub, &error) as Data? else {
            throw CSRError.export(cfError(error))   // PKCS#1 RSAPublicKey DER
        }
        guard let privData = SecKeyCopyExternalRepresentation(priv, &error) as Data? else {
            throw CSRError.export(cfError(error))   // PKCS#1 RSAPrivateKey DER
        }

        // 2. subjectPublicKeyInfo = SEQ { SEQ { OID rsaEncryption, NULL }, BITSTRING(pkcs1) }
        let rsaOID = DER.oid([1, 2, 840, 113549, 1, 1, 1])
        let spki = DER.sequence(DER.sequence(rsaOID + DER.null()) + DER.bitString(pubData))

        // 3. subject Name = SEQ { RDN(CN), RDN(emailAddress) }
        let cn = DER.rdn(oid: [2, 5, 4, 3], utf8: commonName)
        let email = DER.rdn(oid: [1, 2, 840, 113549, 1, 9, 1], ia5: emailAddress)
        let subject = DER.sequence(cn + email)

        // 4. CertificationRequestInfo = SEQ { INTEGER 0, subject, spki, [0] SET{} }
        let attributes = DER.contextConstructed(0, DER.set(Data()))
        let cri = DER.sequence(DER.integer(0) + subject + spki + attributes)

        // 5. Sign the CRI with SHA256/RSA-PKCS1.
        guard let signature = SecKeyCreateSignature(
            priv, .rsaSignatureMessagePKCS1v15SHA256, cri as CFData, &error) as Data? else {
            throw CSRError.sign(cfError(error))
        }
        let sigAlg = DER.sequence(DER.oid([1, 2, 840, 113549, 1, 1, 11]) + DER.null()) // sha256WithRSAEncryption
        let csr = DER.sequence(cri + sigAlg + DER.bitString(signature))

        return Result(
            privateKeyPEM: pem(privData, label: "RSA PRIVATE KEY"),
            csrPEM: pem(csr, label: "CERTIFICATE REQUEST")
        )
    }

    private static func cfError(_ e: Unmanaged<CFError>?) -> String {
        guard let e = e?.takeRetainedValue() else { return "unknown" }
        return CFErrorCopyDescription(e) as String? ?? "unknown"
    }

    private static func pem(_ der: Data, label: String) -> String {
        let b64 = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN \(label)-----\n\(b64)\n-----END \(label)-----\n"
    }
}

/// Minimal DER (TLV) encoder — just the primitives a CSR needs.
enum DER {
    static func len(_ n: Int) -> Data {
        if n < 0x80 { return Data([UInt8(n)]) }
        var v = n, bytes: [UInt8] = []
        while v > 0 { bytes.insert(UInt8(v & 0xff), at: 0); v >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
    static func tlv(_ tag: UInt8, _ body: Data) -> Data { Data([tag]) + len(body.count) + body }

    static func sequence(_ body: Data) -> Data { tlv(0x30, body) }
    static func set(_ body: Data) -> Data { tlv(0x31, body) }
    static func integer(_ v: Int) -> Data { tlv(0x02, Data([UInt8(v)])) }
    static func null() -> Data { Data([0x05, 0x00]) }
    static func bitString(_ d: Data) -> Data { tlv(0x03, Data([0x00]) + d) }        // 0 unused bits
    static func utf8(_ s: String) -> Data { tlv(0x0c, Data(s.utf8)) }
    static func ia5(_ s: String) -> Data { tlv(0x16, Data(s.utf8)) }
    static func contextConstructed(_ n: UInt8, _ body: Data) -> Data { tlv(0xA0 | n, body) }

    static func oid(_ parts: [Int]) -> Data {
        var bytes: [UInt8] = [UInt8(parts[0] * 40 + parts[1])]
        for p in parts.dropFirst(2) {
            var v = p, stack: [UInt8] = []
            repeat { stack.insert(UInt8(v & 0x7f), at: 0); v >>= 7 } while v > 0
            for i in 0..<stack.count - 1 { stack[i] |= 0x80 }
            bytes += stack
        }
        return tlv(0x06, Data(bytes))
    }

    /// RelativeDistinguishedName = SET { SEQ { OID, value } }
    static func rdn(oid o: [Int], utf8 value: String) -> Data { set(sequence(oid(o) + utf8(value))) }
    static func rdn(oid o: [Int], ia5 value: String) -> Data { set(sequence(oid(o) + ia5(value))) }
}
