package dev.sctvdl.data.programmes.remote
import dev.sctvdl.data.programmes.remote.ProgrammeRemoteDataSource
import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.AppException
import dev.sctvdl.domain.common.ErrorKind
import javax.inject.Inject
import okhttp3.ResponseBody

internal class RetrofitProgrammeRemoteDataSource @Inject constructor(private val api: ProgrammeApi) :
    ProgrammeRemoteDataSource {
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
