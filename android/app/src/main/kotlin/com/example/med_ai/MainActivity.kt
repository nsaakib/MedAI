package com.example.med_ai

import android.content.Intent
import android.speech.RecognizerIntent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
private var medaiSpeechResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "medai/voice")
            .setMethodCallHandler { call, result ->
                if (call.method != "dictate") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (medaiSpeechResult != null) {
                    result.error("busy", "Speech recognition is already open.", null)
                    return@setMethodCallHandler
                }
                val language = if (call.arguments == "bn-BD") "bn-BD" else "en-US"
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                }
                medaiSpeechResult = result
                try {
                    startActivityForResult(intent, 4847)
                } catch (_: Exception) {
                    medaiSpeechResult = null
                    result.error("unavailable", "No speech recognition service is available.", null)
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 4847) return
        val reply = medaiSpeechResult
        medaiSpeechResult = null
        reply?.success(if (resultCode == RESULT_OK)
            data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            else null)
    }
}
