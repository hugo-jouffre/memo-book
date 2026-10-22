package com.memobook.feature

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.memobook.core.ChatCopy
import com.memobook.design.BrandButton
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.MemoBookSpacing
import com.memobook.feature.chat.ChatMetrics
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

/**
 * Où vivent les photos jointes, le temps qu'on les regarde. Jumeau de
 * `ChatPhotoFile` (`PhotoFlow.swift`).
 *
 * Dans les **caches** (`cacheDir`) et non dans les fichiers de l'app, pour la
 * même raison que les vocaux : une photo partie sur le serveur n'a plus à être
 * gardée, et le système peut reprendre la place s'il en manque. C'est aussi ce
 * qui évite de sauvegarder des fichiers qui ne sont que du transit.
 */
object ChatPhotoFile {
    private fun directory(cacheDirectory: File) = File(cacheDirectory, "ChatPhotos")

    @Throws(IOException::class)
    fun save(cacheDirectory: File, data: ByteArray, id: String): File {
        val directory = directory(cacheDirectory)
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("Impossible de créer ${directory.path}")
        val file = File(directory, "$id.jpg")
        // Écrit à côté puis renommé : le `.atomic` d'iOS.
        val partial = File(directory, "$id.jpg.part")
        partial.writeBytes(data)
        if (!partial.renameTo(file)) {
            partial.delete()
            throw IOException("Impossible d’écrire ${file.path}")
        }
        return file
    }

    fun removeAll(cacheDirectory: File) {
        directory(cacheDirectory).deleteRecursively()
    }
}

/**
 * Comment on choisit une photo — pour la conversation, pour sa photo de
 * profil, pour une couverture. Jumeau de `PhotoFlow.swift`.
 *
 * **Le geste suit le système, pas MemoBook.** On demande ce qu'on veut faire —
 * prendre une photo maintenant, ou en choisir une —, puis les deux commandes du
 * système font le reste.
 *
 * **Android n'a pas l'accès à la photothèque d'iOS à demander.** Le sélecteur
 * de photos du système (`PickVisualMedia`) ne donne à l'app que les images
 * qu'on y choisit, sans permission de stockage : la question « Tout » ou
 * « Sélectionner des photos… » d'iOS n'existe pas, et son refus non plus.
 * L'appareil photo passe par l'app photo du système (`TakePicture`), qui écrit
 * dans un fichier du cache que l'app lui prête ; l'app ne demande la caméra que
 * si une bibliothèque l'a déclarée dans le manifeste fusionné — Android exige
 * alors qu'elle soit accordée.
 *
 * Un refus n'est pas une impasse silencieuse : l'écran dit ce qui manque.
 *
 * L'état est ici ; ce qui s'ouvre — la feuille de choix, le sélecteur,
 * l'appareil photo — est posé par [PhotoFlowHost].
 */
@Stable
class PhotoFlow {
    /** La feuille de choix est ouverte. */
    var isChoosing by mutableStateOf(false)

    /** Le sélecteur de photos est demandé. */
    var isPickingFromLibrary by mutableStateOf(false)

    /** L'appareil photo est demandé, ou ouvert. */
    var isTakingPhoto by mutableStateOf(false)

    /** Ce qui manque, dit à l'utilisateur. Affiché en bandeau par l'écran. */
    var deniedMessage: String? by mutableStateOf(null)
        private set

    /**
     * La feuille propose aussi de **retirer** la photo en place — posé par
     * [PhotoFlowHost] quand il reçoit `onRemove`. Sur iOS, c'est ce qui garde la
     * feuille ouverte quand la photothèque est refusée (recette du
     * 30/09/2026) ; ici rien ne la refuse.
     */
    var offersRemoval by mutableStateOf(false)
        internal set

    /**
     * L'appareil photo existe. Faux sur un émulateur sans caméra, et sur un
     * appareil qui n'en a pas : proposer « Prendre une photo » là-dessus
     * n'ouvrirait rien. Lu sur le téléphone par [PhotoFlowHost].
     */
    var canTakePhoto by mutableStateOf(true)
        internal set

    /** Le geste d'entrée : on demande quoi faire. */
    fun begin() {
        deniedMessage = null
        isChoosing = true
    }

    fun chooseLibrary() {
        isPickingFromLibrary = true
    }

    /** L'appareil photo a sa propre autorisation, quand l'app en déclare une — voir [PhotoFlow]. */
    fun chooseCamera() {
        if (!canTakePhoto) {
            deniedMessage = ChatCopy.Photos.cameraUnavailable
            return
        }
        isTakingPhoto = true
    }

    fun dismissDenial() {
        deniedMessage = null
    }

    internal fun deny(message: String) {
        isTakingPhoto = false
        deniedMessage = message
    }

    companion object {
        /**
         * La qualité du JPEG d'une photo prise : 0,85 — au-delà, le poids double
         * sans que l'œil y gagne quoi que ce soit à la taille d'une page de
         * carnet. La même que sur iOS.
         */
        const val JPEG_QUALITY = 85

        /** Le fichier que l'app photo du système remplit — toujours le même, pour le retrouver après une mort du processus. */
        internal fun captureFile(context: Context): File =
            File(File(context.cacheDir, "camera").apply { mkdirs() }, "capture.jpg")

        /** L'autorité du `FileProvider` déclaré dans le manifeste de `:app`. */
        internal fun authority(context: Context): String = "${context.packageName}.photos"

        /**
         * La photo prise, redressée et réécrite en JPEG à [JPEG_QUALITY] — le
         * `jpegData(compressionQuality: 0.85)` d'iOS, sur l'image entière.
         * L'orientation EXIF est appliquée : une photo prise en portrait ne
         * doit pas se coucher. `null` si le fichier n'est pas une image lisible.
         */
        internal fun cameraJpeg(file: File): ByteArray? {
            if (!file.isFile || file.length() == 0L) return null
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.path, bounds)
            // Un garde-fou, que l'UIImage d'iOS n'a pas : au-delà de 8 000 px
            // de côté, l'image entière ne tiendrait pas en mémoire.
            var sample = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / sample > MAX_DECODED_SIDE) sample *= 2
            val decoded = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
            val upright = decoded.applyingOrientation(runCatching { ExifInterface(file.path) }.getOrNull())
            return ByteArrayOutputStream().use { out ->
                upright.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
                out.toByteArray()
            }
        }

        private const val MAX_DECODED_SIDE = 8_000

        private fun Bitmap.applyingOrientation(exif: ExifInterface?): Bitmap {
            val orientation = exif?.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
                ?: ExifInterface.ORIENTATION_NORMAL
            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> matrix.apply { postRotate(90f); postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_TRANSVERSE -> matrix.apply { postRotate(270f); postScale(-1f, 1f) }
                else -> return this
            }
            return Bitmap.createBitmap(this, 0, 0, width, height, matrix, true)
        }

        /** Les octets d'une image choisie, tels quels — ceux que le sélecteur donne, comme `loadTransferable` sur iOS. */
        internal fun read(context: Context, uri: Uri): ByteArray? =
            runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull()

        /** Une bibliothèque a déclaré la caméra : Android exige alors qu'elle soit accordée pour `TakePicture`. */
        internal fun declaresCameraPermission(context: Context): Boolean = runCatching {
            @Suppress("DEPRECATION")
            val info = context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
            info.requestedPermissions.orEmpty().contains(Manifest.permission.CAMERA)
        }.getOrDefault(false)
    }
}

/** Le parcours de choix d'une photo, gardé par l'écran — le `@State var photos = PhotoFlow()` d'iOS. */
@Composable
fun rememberPhotoFlow(): PhotoFlow = remember { PhotoFlow() }

/**
 * Pose le parcours de choix d'une photo : la feuille de choix, le sélecteur de
 * photos, et l'appareil photo — le `.photoFlow(_:title:maxSelection:onRemove:onPicked:)`
 * d'iOS. À poser n'importe où dans l'écran, comme une feuille.
 *
 * @param title ce que la feuille de choix annonce — « Ajouter une photo » dans
 *   la conversation, « Photo de profil » sur le profil.
 * @param maxSelection combien de photos le sélecteur laisse choisir.
 * @param onRemove **retirer la photo en place**, quand il y en a une — le profil
 *   revient alors à ses initiales (Hugo, 29/09/2026). `null` n'ajoute rien à la
 *   feuille.
 * @param onPicked les images choisies, dans l'ordre du choix.
 */
@Composable
fun PhotoFlowHost(
    flow: PhotoFlow,
    title: String = ChatCopy.Photos.title,
    maxSelection: Int = ChatMetrics.visiblePhotoCount,
    onRemove: (() -> Unit)? = null,
    onPicked: (List<ByteArray>) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val picked by rememberUpdatedState(onPicked)

    SideEffect {
        flow.offersRemoval = onRemove != null
        flow.canTakePhoto = context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
    }

    // Les images sont lues **en série** : l'ordre du choix est celui du récit.
    val deliver: (List<Uri>) -> Unit = { uris ->
        if (uris.isNotEmpty()) {
            scope.launch {
                val images = withContext(Dispatchers.IO) { uris.mapNotNull { PhotoFlow.read(context, it) } }
                picked(images)
            }
        }
    }
    val pickOne = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> deliver(listOfNotNull(uri)) }
    // Le sélecteur multiple exige au moins deux images ; un seul choix passe par l'autre.
    val pickMany = rememberLauncherForActivityResult(
        remember(maxSelection) { ActivityResultContracts.PickMultipleVisualMedia(maxOf(2, maxSelection)) },
    ) { uris -> deliver(uris) }

    val takePicture = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { saved ->
        flow.isTakingPhoto = false
        if (!saved) return@rememberLauncherForActivityResult
        scope.launch {
            val data = withContext(Dispatchers.IO) { PhotoFlow.cameraJpeg(PhotoFlow.captureFile(context)) }
            if (data != null) picked(listOf(data))
        }
    }
    val launchCamera: () -> Unit = {
        try {
            val uri = FileProvider.getUriForFile(context, PhotoFlow.authority(context), PhotoFlow.captureFile(context))
            takePicture.launch(uri)
        } catch (_: ActivityNotFoundException) {
            flow.deny(ChatCopy.Photos.cameraUnavailable)
        } catch (_: IllegalArgumentException) {
            flow.deny(ChatCopy.Photos.cameraUnavailable)
        }
    }
    val cameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) launchCamera() else flow.deny(ChatCopy.Photos.cameraDenied)
    }

    LaunchedEffect(flow.isPickingFromLibrary) {
        if (!flow.isPickingFromLibrary) return@LaunchedEffect
        flow.isPickingFromLibrary = false
        val request = PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
        if (maxSelection > 1) pickMany.launch(request) else pickOne.launch(request)
    }

    LaunchedEffect(flow.isTakingPhoto) {
        if (!flow.isTakingPhoto) return@LaunchedEffect
        val needsGrant = PhotoFlow.declaresCameraPermission(context) &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED
        if (needsGrant) cameraPermission.launch(Manifest.permission.CAMERA) else launchCamera()
    }

    // La feuille de choix — le `confirmationDialog` d'iOS.
    BrandSheetHost(isPresented = flow.isChoosing, onDismissRequest = { flow.isChoosing = false }) {
        BrandSheet(title) {
            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                // L'ordre suit celui d'iOS : l'action qui crée quelque chose
                // d'abord, celle qui puise dans l'existant ensuite.
                if (flow.canTakePhoto) {
                    BrandButton(ChatCopy.Photos.takeOne, style = BrandButton.Style.Secondary, fillsWidth = true) {
                        flow.isChoosing = false
                        flow.chooseCamera()
                    }
                }
                BrandButton(ChatCopy.Photos.fromLibrary, style = BrandButton.Style.Secondary, fillsWidth = true) {
                    flow.isChoosing = false
                    flow.chooseLibrary()
                }
                // Retirer vient en dernier, et en rouge : c'est l'action qui
                // défait.
                if (onRemove != null) {
                    BrandButton(ChatCopy.Photos.remove, style = BrandButton.Style.Destructive, fillsWidth = true) {
                        flow.isChoosing = false
                        onRemove()
                    }
                }
                BrandButton(ChatCopy.Photos.cancel, style = BrandButton.Style.Tertiary, fillsWidth = true) {
                    flow.isChoosing = false
                }
            }
        }
    }
}
