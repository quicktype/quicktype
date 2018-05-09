package quicktype

import java.io.File
import java.io.InputStream

fun main(args: Array<String>) {
	val stream = File("sample.json").inputStream()
	val json = stream.bufferedReader(Charsets.UTF_8).use { it.readText() }

	val top = TopLevel.fromJson(json)
	println(top!!.toJson())
}
