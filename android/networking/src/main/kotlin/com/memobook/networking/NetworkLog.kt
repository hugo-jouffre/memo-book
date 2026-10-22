package com.memobook.networking

import okhttp3.HttpUrl
import okhttp3.Request
import java.io.EOFException
import java.io.InterruptedIOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketException
import java.net.UnknownHostException
import java.net.UnknownServiceException
import java.util.logging.Level
import java.util.logging.Logger
import kotlin.math.roundToLong

/**
 * La trace des appels réseau, **en développement seulement**. Le jumeau de
 * `MemoBookNetworking/NetworkLog.swift`.
 *
 * Elle existe parce qu'une app qui échoue silencieusement coûte plus cher
 * qu'elle ne le laisse croire : sans trace, un serveur local arrêté et un bug
 * d'écran se ressemblent exactement — un écran vide et une phrase sur le
 * réseau. Une ligne par requête suffit à trancher en une seconde.
 *
 * Le `#if DEBUG` d'iOS devient une **présence** : le client ne trace que si on
 * lui donne un `NetworkLog` (`MemoBookApiClient(networkLog = …)`), ce que
 * l'app ne fait qu'en Debug. Les lignes partent dans un [Sink] : le journal
 * système d'Android en vrai (`AndroidLogSink`, dans un fichier à part, à lire
 * avec `adb logcat -s MemoBook.réseau`), [JavaLoggingSink] sur la JVM.
 *
 * On n'y écrit qu'une méthode, un chemin et un code de statut, jamais un corps
 * de requête ni un jeton.
 */
class NetworkLog(private val sink: Sink = JavaLoggingSink()) {

    /** Où vont les lignes, à trois niveaux — ceux d'`os.Logger` dont iOS se sert. */
    interface Sink {
        fun debug(line: String)
        fun notice(line: String)
        fun error(line: String)
    }

    /**
     * `java.util.logging` : pour la JVM — tests, outils de bureau. Et non
     * `System.Logger`, que la bibliothèque standard d'Android n'a pas : ce
     * fichier compile pour les deux.
     */
    class JavaLoggingSink(name: String = "com.memobook.app.réseau") : Sink {
        private val logger = Logger.getLogger(name)
        override fun debug(line: String) = logger.log(Level.FINE, line)
        override fun notice(line: String) = logger.log(Level.INFO, line)
        override fun error(line: String) = logger.log(Level.SEVERE, line)
    }

    /** Un instant de départ, en nanosecondes monotones (le `ContinuousClock` d'iOS). */
    fun start(request: Request): Long {
        sink.debug("→ ${label(request)}")
        return System.nanoTime()
    }

    fun finish(request: Request, statusCode: Int, since: Long) {
        val line = "$statusCode ${label(request)} ${duration(since)}"

        // Un 4xx/5xx n'est pas un incident de l'app, mais c'est presque
        // toujours ce qu'on cherche : il monte donc d'un niveau pour ressortir
        // dans une console bavarde.
        if (statusCode in 200 until 400) {
            sink.debug("← $line")
        } else {
            sink.error("← $line")
        }
    }

    fun fail(request: Request, error: Throwable, since: Long) {
        sink.error("✗ ${label(request)} ${duration(since)} — ${error.shortDescription}")
    }

    /**
     * La bascule sur l'adresse de secours : une ligne, une fois par session,
     * pour qu'on sache **à qui** l'app parle désormais. Sans elle, un émulateur
     * qui écrit dans la base de production en croyant parler au Mac serait
     * exactement le genre de chose qu'on découvre trop tard.
     */
    fun fallback(from: HttpUrl?, to: HttpUrl?) {
        sink.notice(
            "↪︎ rien n’écoute sur ${from?.host ?: "?"} : " +
                "bascule sur ${to?.host ?: "?"} pour la suite de la session",
        )
    }

    private fun label(request: Request): String = "${request.method} ${request.url.encodedPath}"

    private fun duration(since: Long): String {
        val milliseconds = (System.nanoTime() - since) / 1_000_000.0
        return "(${milliseconds.roundToLong()} ms)"
    }
}

/**
 * L'erreur de transport en clair. `localizedMessage` dit « failed to connect
 * to /127.0.0.1 (port 3000) from … » là où le type, lui, nomme la panne —
 * le `URLError.shortDescription` d'iOS, sur les exceptions de `java.net`.
 */
val Throwable.shortDescription: String
    get() = when (this) {
        is NoRouteToHostException -> "pas de réseau"
        is ConnectException -> "connexion refusée (rien n’écoute)"
        is UnknownHostException -> "hôte introuvable"
        is InterruptedIOException -> "délai dépassé"
        is SocketException, is EOFException -> "connexion perdue en cours de route"
        is UnknownServiceException -> "bloqué par la politique réseau (http en clair)"
        else -> "$localizedMessage [${this::class.java.simpleName}]"
    }
