package dev.sctvdl.data.network

import dev.sctvdl.data.repository.ProgrammeSource
import dev.sctvdl.domain.AppError
import dev.sctvdl.domain.AppException
import dev.sctvdl.domain.ErrorKind
import javax.inject.Inject
import okhttp3.ResponseBody
import retrofit2.http.GET
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.Streaming

interface ProgrammeApi {
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

class RetrofitProgrammeSource @Inject constructor(private val api: ProgrammeApi) : ProgrammeSource {
    override suspend fun programmes() = read(api.programmes())
    override suspend fun dates(programmeId: String) = read(api.dates(checkedId(programmeId)))
    override suspend fun contents(programmeId: String, dateId: String) = read(
        api.contents(
            checkedId(programmeId),
            checkedId(dateId)
        )
    )

    private fun checkedId(value: String): String = value.also { require(it.matches(Regex("\\d+"))) }

    private fun read(body: ResponseBody): String = body.use {
        val source = body.source()
        val limit = 2L * 1024 * 1024
        source.request(limit + 1)
        if (source.buffer.size > limit) {
            throw AppException(AppError(ErrorKind.InvalidData, "节目数据过大，请稍后重试"))
        }
        source.readUtf8()
    }
}
