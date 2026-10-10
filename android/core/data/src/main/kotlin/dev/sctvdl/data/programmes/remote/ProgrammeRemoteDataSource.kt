package dev.sctvdl.data.programmes.remote

internal interface ProgrammeRemoteDataSource {
    suspend fun programmes(): String

    suspend fun dates(programmeId: String): String

    suspend fun contents(programmeId: String, dateId: String): String
}
