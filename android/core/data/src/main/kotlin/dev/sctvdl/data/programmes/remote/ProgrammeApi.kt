package dev.sctvdl.data.programmes.remote

import okhttp3.ResponseBody
import retrofit2.http.GET
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.Streaming

internal interface ProgrammeApi {
    @Streaming
    @GET("app/v1/programs")
    suspend fun programmes(@Query("page") page: Int = 0, @Query("size") size: Int = 100): ResponseBody

    @Streaming
    @GET("app/v1/programs/{programmeId}/dates/list")
    suspend fun dates(@Path("programmeId") programmeId: String): ResponseBody

    @Streaming
    @GET("app/v1/programs/{programmeId}/dates/{dateId}/contents/list")
    suspend fun contents(@Path("programmeId") programmeId: String, @Path("dateId") dateId: String): ResponseBody
}
