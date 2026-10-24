import Foundation
import SCTVCore

public struct GuestRequestProfile: Sendable {
    public let deviceID: UUID

    public init(deviceID: UUID) { self.deviceID = deviceID }

    public func apply(to original: URLRequest) -> URLRequest {
        var request = original
        request.setValue("", forHTTPHeaderField: "userId")
        request.setValue("", forHTTPHeaderField: "Authorization")
        request.setValue("", forHTTPHeaderField: "captchaId")
        request.setValue(deviceID.uuidString, forHTTPHeaderField: "deviceId")
        request.setValue("google", forHTTPHeaderField: "deviceBrand")
        request.setValue("Pixel 8", forHTTPHeaderField: "deviceModel")
        request.setValue("14", forHTTPHeaderField: "systemVersion")
        request.setValue("android", forHTTPHeaderField: "deviceType")
        request.setValue("9.6.1.5", forHTTPHeaderField: "appVersion")
        request.setValue(UpstreamRequestProfile.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
