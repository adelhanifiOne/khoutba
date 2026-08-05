package com.adelhanifi.khoutba

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import kotlin.concurrent.thread

/**
 * Extrait la piste sonore d'une vidéo dans un fichier .m4a.
 *
 * MediaExtractor lit les échantillons audio, MediaMuxer les réécrit tels quels
 * dans un conteneur MP4 : aucun ré-encodage, donc aucune perte de qualité et
 * quelques secondes de traitement là où un transcodage prendrait des minutes.
 * Une vidéo de prêche de 700 Mo donne une dizaine de Mo.
 */
class ExtractionAudio(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val canal = MethodChannel(messenger, "khoutba/extraction")
    private val principal = Handler(Looper.getMainLooper())

    init {
        canal.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "espaceLibre") {
            result.success(espaceLibre())
            return
        }
        if (call.method != "extraire") {
            result.notImplemented()
            return
        }
        val source = call.argument<String>("source")
        val destination = call.argument<String>("destination")
        if (source == null || destination == null) {
            result.error("arguments", "source et destination attendues", null)
            return
        }
        // Plusieurs centaines de Mo à parcourir : jamais sur le fil principal.
        thread(name = "extraction-audio") { extraire(source, destination, result) }
    }

    /** Octets disponibles sur la mémoire interne, ou -1 si la lecture échoue. */
    private fun espaceLibre(): Long =
        try {
            StatFs(Environment.getDataDirectory().path).availableBytes
        } catch (e: Throwable) {
            -1L
        }

    private fun extraire(source: String, destination: String, result: MethodChannel.Result) {
        val sortie = File(destination)
        sortie.delete()
        var extracteur: MediaExtractor? = null
        var assembleur: MediaMuxer? = null
        try {
            val ex = MediaExtractor().also { extracteur = it }
            ex.setDataSource(source)

            var piste = -1
            var format: MediaFormat? = null
            for (i in 0 until ex.trackCount) {
                val f = ex.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    piste = i
                    format = f
                    break
                }
            }
            if (format == null) {
                repondre(result) { it.error("sans_audio", "Vidéo sans piste sonore.", null) }
                return
            }
            ex.selectTrack(piste)

            val mux = MediaMuxer(destination, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                .also { assembleur = it }
            val pisteSortie = mux.addTrack(format)
            mux.start()

            // Un échantillon audio fait quelques Ko ; la borne haute évite qu'un
            // fichier annonçant n'importe quoi fasse exploser la mémoire.
            val tailleTampon =
                if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE))
                    format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
                        .coerceIn(64 * 1024, 2 * 1024 * 1024)
                else 512 * 1024
            val tampon = ByteBuffer.allocate(tailleTampon)
            val info = MediaCodec.BufferInfo()
            val duree =
                if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION)
                else 0L
            var dernierPourcent = -1

            while (true) {
                val lus = ex.readSampleData(tampon, 0)
                if (lus < 0) break
                info.offset = 0
                info.size = lus
                info.presentationTimeUs = ex.sampleTime
                // SAMPLE_FLAG_ENCRYPTED et BUFFER_FLAG_CODEC_CONFIG partagent la
                // même valeur : recopier les drapeaux tels quels corromprait le
                // fichier. Seul « image clé » a un sens ici.
                info.flags =
                    if (ex.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0)
                        MediaCodec.BUFFER_FLAG_KEY_FRAME
                    else 0
                mux.writeSampleData(pisteSortie, tampon, info)

                if (duree > 0) {
                    val pourcent = (info.presentationTimeUs * 100 / duree).toInt()
                    if (pourcent != dernierPourcent) {
                        dernierPourcent = pourcent
                        principal.post { canal.invokeMethod("progression", pourcent / 100.0) }
                    }
                }
                ex.advance()
            }

            // Fermer avant de répondre : c'est stop() qui finalise le MP4.
            mux.stop()
            mux.release()
            assembleur = null
            ex.release()
            extracteur = null
            repondre(result) { it.success(destination) }
        } catch (e: Throwable) {
            sortie.delete()
            repondre(result) { it.error("echec", e.message ?: e.toString(), null) }
        } finally {
            try { assembleur?.release() } catch (ignore: Throwable) {}
            try { extracteur?.release() } catch (ignore: Throwable) {}
        }
    }

    /** Un MethodChannel.Result ne se répond que depuis le fil principal. */
    private fun repondre(result: MethodChannel.Result, action: (MethodChannel.Result) -> Unit) {
        principal.post { action(result) }
    }
}
