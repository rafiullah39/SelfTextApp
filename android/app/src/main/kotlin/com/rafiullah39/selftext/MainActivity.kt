package com.rafiullah39.selftext

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var voiceResult: MethodChannel.Result? = null
    private var events: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null
    private val handler = Handler(Looper.getMainLooper())
    private val chunks = mutableListOf<String>()
    private var partial = ""
    private var locale = "auto"
    private var stopping = false
    private var errors = 0
    private val permissionRequest = 7214
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger,"selftext/voice-events").setStreamHandler(object: EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { events=sink }
            override fun onCancel(arguments: Any?) { events=null }
        })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"selftext/voice").setMethodCallHandler { call,result ->
            when(call.method) {
                "recognize" -> {
                    if(voiceResult!=null){result.error("busy","Voice capture is already active",null);return@setMethodCallHandler}
                    voiceResult=result;locale=call.argument<String>("locale")?:"auto"
                    chunks.clear();partial="";stopping=false;errors=0
                    if(checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO),permissionRequest)
                    } else beginVoice()
                }
                "stop" -> {
                    stopping=true;handler.removeCallbacksAndMessages(null)
                    if(recognizer==null)finishVoice() else {
                        recognizer?.stopListening()
                        handler.postDelayed({finishVoice()},1200)
                    }
                    result.success(null)
                }
                "cancel" -> { finishVoice(cancel=true);result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    private fun text(): String = (chunks+listOf(partial)).filter{it.isNotBlank()}.joinToString(" ")
    private fun emit() { events?.success(text()) }
    private fun append(value:String) { if(value.isNotBlank())chunks.add(value.trim());partial="";emit() }
    private fun beginVoice() {
        if(voiceResult==null)return
        if(!SpeechRecognizer.isRecognitionAvailable(this)){fail("No speech service is available. You can type your message instead.");return}
        recognizer=SpeechRecognizer.createSpeechRecognizer(this)
        recognizer?.setRecognitionListener(object: RecognitionListener {
            override fun onReadyForSpeech(params:Bundle?) { emit() }
            override fun onBeginningOfSpeech() { errors=0 }
            override fun onRmsChanged(rmsdB:Float) {}
            override fun onBufferReceived(buffer:ByteArray?) {}
            override fun onEndOfSpeech() {} // A pause ends a segment, never the user's session.
            override fun onPartialResults(results:Bundle?) {
                if(voiceResult==null)return
                partial=results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?:partial;emit()
            }
            override fun onResults(results:Bundle?) {
                if(voiceResult==null)return
                append(results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?:partial)
                if(stopping)finishVoice() else restart()
            }
            override fun onError(error:Int) {
                if(voiceResult==null)return
                if(partial.isNotBlank())append(partial)
                if(stopping){finishVoice();return}
                if(error==SpeechRecognizer.ERROR_NO_MATCH||error==SpeechRecognizer.ERROR_SPEECH_TIMEOUT){restart();return}
                errors++
                if(errors<3)restart() else fail(if(error==SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS)"Allow microphone access to speak." else "The speech service stopped. Check your connection or language setting. Your captured text is kept for review.")
            }
            override fun onEvent(eventType:Int,params:Bundle?) {}
        })
        listen()
    }
    private fun restart(){handler.postDelayed({if(voiceResult!=null&&!stopping)listen()},450)}
    private fun listen(){
        if(voiceResult==null||stopping)return
        val intent=Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS,true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS,1)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,5000L)
            if(locale!="auto")putExtra(RecognizerIntent.EXTRA_LANGUAGE,locale)
            if(locale=="auto"&&Build.VERSION.SDK_INT>=34){
                putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_DETECTION,true)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_DETECTION_ALLOWED_LANGUAGES,arrayListOf("en-US","en-GB","ur-PK","ur-IN"))
                putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_SWITCH,RecognizerIntent.LANGUAGE_SWITCH_BALANCED)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_SWITCH_ALLOWED_LANGUAGES,arrayListOf("en-US","en-GB","ur-PK","ur-IN"))
            }
        }
        try{recognizer?.startListening(intent)}catch(error:Exception){fail("Could not start your phone's speech service. Try again or type your message.")}
    }
    private fun finishVoice(cancel:Boolean=false){
        val result=voiceResult?:return
        val captured=text();voiceResult=null;stopping=true
        handler.removeCallbacksAndMessages(null);recognizer?.cancel();recognizer?.destroy();recognizer=null
        result.success(if(cancel)null else captured)
    }
    private fun fail(message:String){
        val result=voiceResult?:return
        emit();voiceResult=null;stopping=true
        handler.removeCallbacksAndMessages(null);recognizer?.cancel();recognizer?.destroy();recognizer=null
        result.error("recognition_error",message,null)
    }
    override fun onRequestPermissionsResult(requestCode:Int,permissions:Array<out String>,grantResults:IntArray){
        super.onRequestPermissionsResult(requestCode,permissions,grantResults)
        if(requestCode==permissionRequest&&voiceResult!=null){
            if(grantResults.firstOrNull()==PackageManager.PERMISSION_GRANTED)beginVoice() else fail("Microphone permission was declined. You can still type your message.")
        }
    }
    override fun onPause(){super.onPause();if(voiceResult!=null&&recognizer!=null)finishVoice()}
    override fun onDestroy(){finishVoice(cancel=true);super.onDestroy()}
}
