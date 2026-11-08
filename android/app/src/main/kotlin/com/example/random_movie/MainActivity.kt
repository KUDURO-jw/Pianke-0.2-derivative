// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
package app.pianke.personal

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class UpdateFileProvider : FileProvider()

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.pianke.personal/update")
            .setMethodCallHandler { call, result ->
                if (call.method != "installUpdate") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val versionCode = call.argument<Int>("versionCode")
                if (path == null || versionCode == null) {
                    result.error("invalid_update", "更新信息无效，请重新检查更新", null)
                    return@setMethodCallHandler
                }
                // Parse and verify the archive away from the Android UI thread.
                Thread {
                    try {
                        val file = verifiedUpdateFile(path, versionCode)
                        runOnUiThread {
                            if (isFinishing || isDestroyed) {
                                result.error("activity_closed", "请返回应用后重新点击安装", null)
                            } else {
                                openInstaller(file, result)
                            }
                        }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error("invalid_update", error.message ?: "安装包无效，请重新下载", null)
                        }
                    }
                }.start()
            }
    }

    @Suppress("DEPRECATION")
    private fun verifiedUpdateFile(path: String, expectedCode: Int): File {
        val file = File(path).canonicalFile
        val directory = File(cacheDir, "updates").canonicalFile
        require(file.parentFile == directory && file.name == "Pianke-UI-$expectedCode.apk" && file.isFile) {
            "安装包缓存不存在，请重新下载"
        }
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES
                    else PackageManager.GET_SIGNATURES
        val archive = packageManager.getPackageArchiveInfo(file.path, flags)
            ?: throw IllegalArgumentException("安装包无法解析，请重新下载")
        val installed = packageManager.getPackageInfo(packageName, flags)
        require(archive.packageName == packageName && versionCode(archive) == expectedCode.toLong() &&
                versionCode(archive) > versionCode(installed)) { "安装包版本或包名不匹配，请重新检查更新" }
        require(signatures(archive) == signatures(installed) && signatures(archive).isNotEmpty()) {
            "安装包签名不匹配，已停止安装"
        }
        return file
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signatures(info: PackageInfo): Set<String> =
        (if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures)
            ?.map { it.toCharsString() }?.toSet() ?: emptySet()

    private fun openInstaller(file: File, result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")))
                result.success("permissionRequired")
                return
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.updateprovider", file)
            startActivity(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                clipData = ClipData.newRawUri("片刻更新", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            })
            result.success("launched")
        } catch (error: Exception) {
            result.error("installer_unavailable", "无法打开系统安装界面，请稍后重试", null)
        }
    }
}
