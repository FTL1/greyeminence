import CryptoKit
import Foundation

/// AWS Signature V4 for Bedrock requests.
///
/// Lifted out of `BedrockAPIClient` when a second caller appeared (Titan
/// embeddings). Pure and `Sendable`: given credentials, a region and a body it
/// returns a signed request, with no I/O and no shared state.
struct AWSSigV4Signer: Sendable {
    let credentials: AWSCredentials
    let region: String
    /// AWS service name for the credential scope — "bedrock" for both the
    /// runtime and control-plane endpoints.
    var service: String = "bedrock"

    /// Sign a POST to `host` + `path` carrying `body`.
    ///
    /// `now` is injectable so the canonical request is reproducible in tests;
    /// production always passes the current time.
    func sign(request: URLRequest, body: Data, host: String, path: String, now: Date = Date()) -> URLRequest {
        var req = request

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = dateFormatter.string(from: now)
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: now)

        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let payloadHash = Self.sha256Hex(body)

        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(host, forHTTPHeaderField: "Host")
        req.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        req.setValue(payloadHash, forHTTPHeaderField: "X-Amz-Content-Sha256")
        if let sessionToken = credentials.sessionToken {
            req.setValue(sessionToken, forHTTPHeaderField: "X-Amz-Security-Token")
        }

        // Canonical headers must be sorted by lowercase header name.
        var signedHeaderNames = ["content-type", "host", "x-amz-content-sha256", "x-amz-date"]
        if credentials.sessionToken != nil {
            signedHeaderNames.append("x-amz-security-token")
        }
        let signedHeaders = signedHeaderNames.joined(separator: ";")

        var canonicalHeaders = ""
        for name in signedHeaderNames {
            canonicalHeaders += "\(name):\(req.value(forHTTPHeaderField: name) ?? "")\n"
        }

        let canonicalRequest = [
            "POST",
            Self.encodePath(path),
            "", // empty query string
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            Self.sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        let kDate = Self.hmac(key: Data("AWS4\(credentials.secretAccessKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = Self.hmac(key: kDate, data: Data(region.utf8))
        let kService = Self.hmac(key: kRegion, data: Data(service.utf8))
        let kSigning = Self.hmac(key: kService, data: Data("aws4_request".utf8))
        let signature = Self.hmac(key: kSigning, data: Data(stringToSign.utf8))
            .map { String(format: "%02x", $0) }.joined()

        req.setValue(
            "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyId)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)",
            forHTTPHeaderField: "Authorization"
        )
        return req
    }

    /// Encode a single path segment (model ID or inference-profile ARN).
    /// Colons and slashes inside an ARN are data, not structure, so they get
    /// percent-encoded too.
    static func encodeSegment(_ segment: String) -> String {
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }

    /// URI-encode a full path per the SigV4 canonical-URI rules: `/` stays a
    /// separator, everything else outside the unreserved set is encoded.
    static func encodePath(_ path: String) -> String {
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func hmac(key: Data, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }
}
