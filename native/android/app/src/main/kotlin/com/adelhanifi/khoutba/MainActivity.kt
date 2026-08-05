package com.adelhanifi.khoutba

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var extraction: ExtractionAudio? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        extraction = ExtractionAudio(flutterEngine.dartExecutor.binaryMessenger)
    }
}
