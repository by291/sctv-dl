package dev.sctvdl.data.network

import okhttp3.Interceptor
import okhttp3.Response

/** Applies the inspected Android guest profile only to the programme API client. */
internal class ProgrammeHeadersInterceptor(
    private val deviceId: () -> String,
    private val brand: String,
    private val model: String,
    private val systemVersion: String
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request().newBuilder()
            .header("userId", "")
            .header("Authorization", "")
            .header("deviceId", deviceId())
            .header("deviceBrand", brand)
            .header("deviceModel", model)
            .header("systemVersion", systemVersion)
            .header("deviceType", "android")
            .header("appVersion", "9.6.1.5")
            .header("captchaId", "")
            .header("User-Agent", "okhttp/4.12.0")
            .build()

        return chain.proceed(request)
    }
}
