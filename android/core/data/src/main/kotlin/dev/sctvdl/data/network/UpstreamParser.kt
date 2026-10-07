package dev.sctvdl.data.network

import dev.sctvdl.domain.AppError
import dev.sctvdl.domain.AppException
import dev.sctvdl.domain.BroadcastDate
import dev.sctvdl.domain.ErrorKind
import dev.sctvdl.domain.Programme
import dev.sctvdl.domain.ProgrammeContent
import java.math.BigInteger
import java.time.LocalDate
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class UpstreamParser {
    private val json = Json { ignoreUnknownKeys = true }

    fun programmes(raw: String): List<Programme> = validate {
        val records = envelope(raw).jsonObject.getValue("records").jsonArray
        records.mapIndexed { index, element ->
            val row = element.jsonObject
            Programme(
                id(row),
                row.string("name") ?: "未命名栏目",
                UrlPolicy.cover(row.string("cover")),
                index
            )
        }.distinctBy(Programme::id)
    }

    fun dates(raw: String): List<BroadcastDate> = validate {
        envelope(raw).jsonArray.map { element ->
            val row = element.jsonObject
            val date = requireNotNull(row.string("date"))
            require(date.matches(Regex("\\d{4}-\\d{2}-\\d{2}")))
            BroadcastDate(id(row), LocalDate.parse(date))
        }.associateBy(BroadcastDate::date).values.sortedByDescending(BroadcastDate::date)
    }

    fun contents(raw: String): List<ProgrammeContent> = validate {
        envelope(raw).jsonArray.map { element ->
            val row = element.jsonObject
            ProgrammeContent(
                id = id(row),
                title = row.string("title") ?: "未命名节目",
                coverUrl = UrlPolicy.cover(row.string("cover")),
                standardUrl = UrlPolicy.media(row.string("video")),
                smoothUrl = UrlPolicy.media(row.string("videoStandard")),
                publishedAt = row.string("pubTime")
            )
        }.distinctBy(ProgrammeContent::id)
    }

    private fun envelope(raw: String): JsonElement {
        val envelope = json.parseToJsonElement(raw).jsonObject
        val status = envelope.getValue("rs").jsonPrimitive
        require(!status.isString)
        val code = requireNotNull(status.intOrNull)
        if (code != 200) {
            throw AppException(
                AppError(
                    ErrorKind.Business,
                    envelope.string("error") ?: "节目服务暂时不可用",
                    code
                )
            )
        }
        return envelope.getValue("data")
    }

    private fun id(row: JsonObject): String {
        val value = row.getValue("id").jsonPrimitive
        if (value.isString) return value.content.also { require(it.matches(Regex("\\d+"))) }

        // Parse the JSON token exactly. A floating-point conversion would destroy large IDs.
        val integer = value.content.toBigDecimal().toBigIntegerExact()
        require(integer >= BigInteger.ZERO && integer <= BigInteger("9007199254740991"))
        return integer.toString()
    }

    private fun JsonObject.string(key: String): String? = (get(key) as? JsonPrimitive)?.takeIf {
        it.isString
    }?.content

    private inline fun <T> validate(block: () -> T): T = try {
        block()
    } catch (error: AppException) {
        throw error
    } catch (error: RuntimeException) {
        throw AppException(AppError(ErrorKind.InvalidData, "节目数据格式有误，请稍后重试"), error)
    }
}
