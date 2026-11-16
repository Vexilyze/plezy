package com.edde746.plezy.updates

import android.app.Activity
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.zip.ZipFile

internal data class ApkIdentity(val packageName: String, val versionCode: Long, val signers: Set<String>)
internal class UpdateValidationException(val code: String, message: String) : Exception(message)

internal fun validateUpdateIdentity(installed: ApkIdentity, candidate: ApkIdentity) {
  if (candidate.packageName != installed.packageName) {
    throw UpdateValidationException("WRONG_PACKAGE", "This APK belongs to a different application.")
  }
  if (candidate.versionCode <= installed.versionCode) {
    throw UpdateValidationException("NOT_NEWER", "This APK is not newer than the installed application.")
  }
  // Deliberately require the current signer set. This fork uses one persistent
  // release key; accepting arbitrary signing history would weaken that contract.
  if (installed.signers.isEmpty() || candidate.signers != installed.signers) {
    throw UpdateValidationException("WRONG_SIGNATURE", "This APK was not signed with the installed application's key.")
  }
}

/** Validates a private APK before handing it to Android's confirmation UI. */
class AndroidUpdatePlugin :
  FlutterPlugin,
  ActivityAware,
  MethodChannel.MethodCallHandler {
  private var context: Context? = null
  private var activity: Activity? = null
  private var channel: MethodChannel? = null
  private var executor = Executors.newSingleThreadExecutor()
  private val main = Handler(Looper.getMainLooper())

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    if (executor.isShutdown) executor = Executors.newSingleThreadExecutor()
    channel = MethodChannel(binding.binaryMessenger, "com.vexilyze/app_updates").also { it.setMethodCallHandler(this) }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel?.setMethodCallHandler(null)
    channel = null
    context = null
    activity = null
    executor.shutdownNow()
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }
  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }
  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }
  override fun onDetachedFromActivity() {
    activity = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val app = context ?: return result.error("UNAVAILABLE", "Updater is unavailable.", null)
    try {
      when (call.method) {
        "deviceInfo" -> {
          val info = packageInfo(app)
          val directory = updateDirectory(app)
          result.success(
            mapOf(
              "versionName" to info.versionName,
              "versionCode" to versionCode(info),
              "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
              "updateDirectory" to directory.path
            )
          )
        }
        "canInstall" -> result.success(canInstall(app))
        "openInstallPermission" -> {
          val host = activity ?: throw UpdateValidationException("UNAVAILABLE", "No foreground activity.")
          val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${app.packageName}"))
          } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
          }
          host.startActivity(intent)
          result.success(null)
        }
        "validateApk", "installApk" -> {
          val path = call.argument<String>("path") ?: throw UpdateValidationException("INVALID_APK", "Missing APK.")
          // Package parsing, certificate collection and ZIP inspection must not
          // block Flutter's platform thread on a TV with slow flash storage.
          executor.execute {
            try {
              val file = validateApk(app, path)
              main.post {
                try {
                  if (context !== app) throw UpdateValidationException("UNAVAILABLE", "Updater was closed.")
                  if (call.method == "installApk") launchInstaller(app, file)
                  result.success(null)
                } catch (error: Exception) {
                  reportError(result, error)
                }
              }
            } catch (error: Exception) {
              main.post { reportError(result, error) }
            }
          }
        }
        else -> result.notImplemented()
      }
    } catch (error: Exception) {
      reportError(result, error)
    }
  }

  private fun updateDirectory(app: Context): File {
    val directory = File(app.cacheDir, "updates")
    if (!directory.isDirectory && !directory.mkdirs()) {
      throw UpdateValidationException("STORAGE", "Unable to create the update cache.")
    }
    // Keep recent handoffs alive for the installer, but reclaim abandoned APKs.
    val cutoff = System.currentTimeMillis() - 2 * 24 * 60 * 60 * 1000L
    directory.listFiles()?.filter { it.isFile && it.lastModified() < cutoff }?.forEach { it.delete() }
    return directory
  }

  @Suppress("DEPRECATION")
  private fun packageInfo(app: Context): PackageInfo = app.packageManager.getPackageInfo(app.packageName, signingFlags())

  private fun signingFlags(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
    PackageManager.GET_SIGNING_CERTIFICATES
  } else {
    @Suppress("DEPRECATION")
    PackageManager.GET_SIGNATURES
  }

  @Suppress("DEPRECATION")
  private fun versionCode(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()

  @Suppress("DEPRECATION")
  private fun identity(info: PackageInfo): ApkIdentity {
    val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      info.signingInfo?.apkContentsSigners
    } else {
      info.signatures
    }
    val signers = signatures?.map {
      MessageDigest.getInstance("SHA-256").digest(it.toByteArray()).joinToString("") { byte -> "%02x".format(byte) }
    }?.toSet() ?: emptySet()
    return ApkIdentity(info.packageName, versionCode(info), signers)
  }

  @Suppress("DEPRECATION")
  private fun validateApk(app: Context, path: String): File {
    val directory = updateDirectory(app).canonicalFile
    val file = File(path).canonicalFile
    if (file.parentFile != directory ||
      !file.name.endsWith(".apk") ||
      !file.isFile ||
      file.length() <= 0L ||
      file.length() > 1024 * 1024 * 1024L
    ) {
      throw UpdateValidationException("INVALID_APK", "The update file is unavailable or outside the private cache.")
    }
    val candidate = app.packageManager.getPackageArchiveInfo(file.path, signingFlags())
      ?: throw UpdateValidationException("INVALID_APK", "Android could not read this APK.")
    validateUpdateIdentity(identity(packageInfo(app)), identity(candidate))
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
      (candidate.applicationInfo?.minSdkVersion ?: 0) > Build.VERSION.SDK_INT
    ) {
      throw UpdateValidationException("UNSUPPORTED", "This update requires a newer Android version.")
    }
    ZipFile(file).use { zip ->
      val abis = zip.entries().asSequence().map { it.name.split('/') }
        .filter { it.size >= 3 && it[0] == "lib" && it.last().endsWith(".so") }
        .map { it[1] }.toSet()
      if (abis.isNotEmpty() && Build.SUPPORTED_ABIS.none { it in abis }) {
        throw UpdateValidationException("UNSUPPORTED", "This APK does not support this device's processor.")
      }
    }
    return file
  }

  private fun canInstall(app: Context): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || app.packageManager.canRequestPackageInstalls()

  private fun launchInstaller(app: Context, file: File) {
    if (!canInstall(app)) throw UpdateValidationException("INSTALL_PERMISSION", "Allow app updates in Android settings.")
    val host = activity ?: throw UpdateValidationException("UNAVAILABLE", "No foreground activity.")
    val uri = FileProvider.getUriForFile(app, "${app.packageName}.updates", file)
    val intent = Intent(Intent.ACTION_VIEW).apply {
      setDataAndType(uri, "application/vnd.android.package-archive")
      addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      clipData = ClipData.newRawUri("Application update", uri)
    }
    // The system package installer owns final confirmation and installation.
    // Never claim success merely because this intent was launched.
    host.startActivity(intent)
  }

  private fun reportError(result: MethodChannel.Result, error: Exception) {
    result.error((error as? UpdateValidationException)?.code ?: "UPDATE_FAILED", error.message, null)
  }
}
