import Foundation

final class MockURLProtocol: URLProtocol {

    /// Each test sets this; the closure receives the request and returns headers + body chunks.
    /// Body chunks are delivered in order, then the loading completes.
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, [Data]))?

    static func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            fatalError("MockURLProtocol.handler not set")
        }
        do {
            let (response, chunks) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in chunks {
                client?.urlProtocol(self, didLoad: chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLSession {
    static func mocked() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: cfg)
    }
}
