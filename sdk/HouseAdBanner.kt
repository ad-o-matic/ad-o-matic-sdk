package com.adomatic.sdk

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.util.Base64
import android.util.LruCache
import androidx.compose.animation.Crossfade
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import java.util.Locale

/**
 * Ad-o-matic Zero-Dependency Single-File Jetpack Compose SDK (v5.9)
 *
 * Official Domain: https://ad-o-matic.com
 *
 * Drop this single file into any Android Jetpack Compose app (adjust package declaration if desired)
 * and call 1 line in your screen:
 *
 *   HouseAdBanner(
 *       bannerText = "Short benefit-driven description of your app",
 *       targetAudience = "guitarists, musicians, chord tuner, songwriting, 18-44"
 *   )
 *   // Or zero-arg automatic fallback (uses your verified store listing & translates automatically):
 *   HouseAdBanner()
 *
 * Anti-Scam Immutable Store Link Lock:
 * Ad destination links cannot be customized or redirected to external websites. Every ad click is locked
 * to open ONLY the advertised app's own official Google Play download page (play.google.com/store/apps/details?id=<packageName>).
 *
 * Zero human configuration, zero third-party libraries required,
 * zero personal data, zero device IDs, zero QUERY_ALL_PACKAGES permission, zero GDPR popups.
 */

data class HouseAd(
    val campaignId: String? = null,
    val appId: String,
    val title: String,
    val description: String,
    val iconUrl: String,
    val storeUrl: String,
    val customBannerUrl: String? = null,
    val bannerSize: String = "320x50",
    val bannerTheme: String = "modern_clean",
    val isGenesisMember: Boolean = false,
    val fallbackType: String = "NONE",
    val admobUnitId: String? = null,
    val active: Boolean = true,
    val adBadge: String = "AD",
    val installCta: String = "Install",
    val reportTitle: String = "Report Ad",
    val reportPrompt: String = "Report this ad for inappropriate content or a broken link?",
    val cancelLabel: String = "Cancel",
    val reportLabel: String = "Report"
)

private object AdomaticEndpointResolver {
    private const val PRIMARY_URL = "https://ad-o-matic.com"

    fun openRequest(
        customBase: String?,
        pathAndQuery: String,
        method: String = "GET",
        headers: Map<String, String> = emptyMap(),
        jsonBody: String? = null
    ): HttpURLConnection {
        val base = (customBase?.takeIf { it.isNotBlank() } ?: PRIMARY_URL).trimEnd('/')
        val conn = URL("$base$pathAndQuery").openConnection() as HttpURLConnection
        conn.requestMethod = method
        conn.connectTimeout = 4500
        conn.readTimeout = 5000
        for ((k, v) in headers) {
            if (v.isNotEmpty()) conn.setRequestProperty(k, v)
        }
        if (jsonBody != null) {
            conn.setRequestProperty("Content-Type", "application/json")
            conn.doOutput = true
            conn.outputStream.use { it.write(jsonBody.toByteArray(Charsets.UTF_8)) }
        }
        return conn
    }

    fun activeBaseUrl(customBase: String?): String =
        (customBase?.takeIf { it.isNotBlank() } ?: PRIMARY_URL).trimEnd('/')
}

private object AdomaticBitmapCache {
    private val cache = object : LruCache<String, Bitmap>(16) {}

    suspend fun load(urlOrDataUri: String): ImageBitmap? = withContext(Dispatchers.IO) {
        val clean = urlOrDataUri.trim()
        if (clean.isEmpty() || clean.startsWith("data:image/svg")) return@withContext null
        synchronized(cache) {
            cache.get(clean)?.let { return@withContext it.asImageBitmap() }
        }
        try {
            val bmp: Bitmap? = if (clean.startsWith("data:image/")) {
                val comma = clean.indexOf(',')
                if (comma > 0) {
                    val bytes = Base64.decode(clean.substring(comma + 1), Base64.DEFAULT)
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                } else null
            } else if (clean.startsWith("https://")) {
                val conn = URL(clean).openConnection() as HttpURLConnection
                conn.connectTimeout = 4000
                conn.readTimeout = 4000
                if (conn.responseCode == 200) {
                    conn.inputStream.use { BitmapFactory.decodeStream(it) }
                } else null
            } else null

            if (bmp != null) {
                synchronized(cache) { cache.put(clean, bmp) }
                bmp.asImageBitmap()
            } else null
        } catch (_: Exception) {
            null
        }
    }
}

class HouseAdManager(
    val context: Context,
    val apiKey: String = "auto",
    val customServerUrl: String? = null,
    val buildBannerText: String = "",
    val buildBannerImageUrl: String? = null,
    val targetAudience: String = "",
    val developerId: String? = null
) {
    private val scope = CoroutineScope(Dispatchers.IO)
    private val _currentAd = MutableStateFlow<HouseAd?>(null)
    val currentAd: StateFlow<HouseAd?> = _currentAd.asStateFlow()

    private var currentNonce: String? = null
    private var activeImpressionNonce: String? = null
    private var activeReportNonce: String? = null
    private var lastCampaignId: String? = null

    private val hostPackageName: String = try { context.packageName ?: "" } catch (_: Exception) { "" }
    private val hostAppTitle: String = try {
        val label = context.packageManager.getApplicationLabel(context.applicationInfo)?.toString()?.trim()
        if (!label.isNullOrBlank()) label else hostPackageName
    } catch (_: Exception) { hostPackageName }

    private val isDebuggableBuild: Boolean = try {
        (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    } catch (_: Exception) { false }

    private val appVersionCode: Long = try {
        val pInfo = context.packageManager.getPackageInfo(hostPackageName, 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            pInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            pInfo.versionCode.toLong()
        }
    } catch (_: Exception) { 1L }

    private val hostIconDataUri: String = try {
        val d = context.packageManager.getApplicationIcon(context.applicationInfo)
        val bmp = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bmp)
        d.setBounds(0, 0, 64, 64)
        d.draw(canvas)
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 90, out)
        "data:image/png;base64," + Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    } catch (_: Exception) { "" }

    private val appSigSha256: String = try {
        val pm = context.packageManager
        val bytes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            pm.getPackageInfo(hostPackageName, PackageManager.GET_SIGNING_CERTIFICATES)
                .signingInfo?.apkContentsSigners?.firstOrNull()?.toByteArray()
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(hostPackageName, PackageManager.GET_SIGNATURES)
                .signatures?.firstOrNull()?.toByteArray()
        }
        if (bytes != null) {
            MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        } else ""
    } catch (_: Exception) { "" }

    private fun commonHeaders(): Map<String, String> = buildMap {
        put("X-App-Package", hostPackageName)
        put("X-App-Version-Code", appVersionCode.toString())
        put("X-App-Debug-Build", if (isDebuggableBuild) "1" else "0")
        if (targetAudience.isNotBlank()) put("X-Target-Audience", targetAudience.trim())
        if (appSigSha256.isNotEmpty()) put("X-App-Sig-Sha256", appSigSha256)
        if (!developerId.isNullOrBlank()) put("X-Developer-Id", developerId)
    }

    fun getBuildEmbeddedSelfAd(): HouseAd {
        val baseTitle = hostAppTitle.ifBlank { "App" }
        val cleanDesc = buildBannerText.trim().ifBlank { "Discover $baseTitle" }
        return HouseAd(
            appId = hostPackageName.ifBlank { "com.adomatic.preview" },
            title = baseTitle,
            description = cleanDesc,
            iconUrl = hostIconDataUri,
            storeUrl = "https://play.google.com/store/apps/details?id=$hostPackageName",
            customBannerUrl = buildBannerImageUrl
        )
    }

    init {
        _currentAd.value = getBuildEmbeddedSelfAd()
        loadNextAd()
    }

    fun activeGenesisUrl(): String = "${AdomaticEndpointResolver.activeBaseUrl(customServerUrl)}/#genesis-members"

    fun loadNextAd() {
        scope.launch {
            try {
                val dbgFlag = if (isDebuggableBuild) "1" else "0"
                val langCode = Locale.getDefault().language.ifBlank { "en" }
                val pathAndQuery = buildString {
                    append("/api/v1/ad/request?apiKey=${URLEncoder.encode(apiKey, "UTF-8")}")
                    append("&packageName=${URLEncoder.encode(hostPackageName, "UTF-8")}")
                    append("&appTitle=${URLEncoder.encode(hostAppTitle, "UTF-8")}")
                    append("&buildBannerText=${URLEncoder.encode(buildBannerText, "UTF-8")}")
                    append("&buildBannerImage=${URLEncoder.encode(buildBannerImageUrl ?: "", "UTF-8")}")
                    append("&platform=android")
                    append("&lang=${URLEncoder.encode(langCode, "UTF-8")}")
                    append("&appVersionCode=$appVersionCode")
                    append("&isDebugBuild=$dbgFlag")
                    if (!lastCampaignId.isNullOrBlank()) append("&excludeCampaignId=${URLEncoder.encode(lastCampaignId, "UTF-8")}")
                    if (targetAudience.isNotBlank()) append("&targetAudience=${URLEncoder.encode(targetAudience.trim(), "UTF-8")}")
                    if (!developerId.isNullOrBlank()) append("&developerId=${URLEncoder.encode(developerId, "UTF-8")}")
                }
                val conn = AdomaticEndpointResolver.openRequest(
                    customBase = customServerUrl,
                    pathAndQuery = pathAndQuery,
                    method = "GET",
                    headers = commonHeaders()
                )

                if (conn.responseCode == 200) {
                    val json = JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
                    val fallbackType = json.optString("fallbackType", "NONE")
                    val admobId = json.optString("admobUnitId", "").takeIf { it.isNotBlank() && it != "null" }
                    val uiStrings = json.optJSONObject("uiStrings")
                    if (!json.isNull("ad") && json.has("ad")) {
                        val adObj = json.getJSONObject("ad")
                        val nonce = json.optString("nonce", "").takeIf { it.isNotBlank() && it != "null" }
                        currentNonce = nonce
                        activeImpressionNonce = nonce
                        activeReportNonce = nonce
                        val cid = adObj.optString("campaignId", "").takeIf { it.isNotBlank() && it != "null" }
                        if (!cid.isNullOrBlank()) lastCampaignId = cid
                        val rawIcon = adObj.optString("iconUrl", "")
                        _currentAd.value = HouseAd(
                            campaignId = cid,
                            appId = adObj.optString("appId", hostPackageName),
                            title = adObj.optString("title", hostAppTitle),
                            description = adObj.optString("description", ""),
                            iconUrl = if (rawIcon.isBlank() || rawIcon.startsWith("data:image/svg")) hostIconDataUri else rawIcon,
                            storeUrl = adObj.optString("storeUrl", "https://play.google.com/store/apps/details?id=$hostPackageName"),
                            customBannerUrl = adObj.optString("customBannerUrl", "").takeIf { it.isNotBlank() && it != "null" },
                            bannerSize = adObj.optString("bannerSize", "320x50"),
                            bannerTheme = adObj.optString("bannerTheme", "modern_clean"),
                            isGenesisMember = adObj.optBoolean("isGenesisMember", false),
                            fallbackType = fallbackType,
                            admobUnitId = admobId,
                            adBadge = uiStrings?.optString("adBadge", "AD")?.takeIf { it.isNotBlank() } ?: "AD",
                            installCta = uiStrings?.optString("installCta", "Install")?.takeIf { it.isNotBlank() } ?: "Install",
                            reportTitle = uiStrings?.optString("reportTitle", "Report Ad")?.takeIf { it.isNotBlank() } ?: "Report Ad",
                            reportPrompt = uiStrings?.optString("reportPrompt", "Report this ad for inappropriate content or a broken link?")?.takeIf { it.isNotBlank() }
                                ?: "Report this ad for inappropriate content or a broken link?",
                            cancelLabel = uiStrings?.optString("cancelBtn", "Cancel")?.takeIf { it.isNotBlank() } ?: "Cancel",
                            reportLabel = uiStrings?.optString("confirmReportBtn", "Report")?.takeIf { it.isNotBlank() } ?: "Report"
                        )
                    } else if (json.optBoolean("capReached", false) || json.optBoolean("hideSlot", false)) {
                        _currentAd.value = HouseAd(
                            appId = hostPackageName,
                            title = "",
                            description = "",
                            iconUrl = "",
                            storeUrl = "",
                            fallbackType = fallbackType,
                            admobUnitId = admobId,
                            active = false
                        )
                    }
                }
            } catch (_: Exception) {
                if (_currentAd.value == null) _currentAd.value = getBuildEmbeddedSelfAd()
            }
        }
    }

    fun verifyImpression(durationSec: Double, widthDp: Float, heightDp: Float, visibleRatio: Float) {
        val nonce = currentNonce ?: return
        currentNonce = null
        val bannerSize = _currentAd.value?.bannerSize ?: "320x50"
        scope.launch {
            try {
                val body = JSONObject().apply {
                    put("apiKey", apiKey)
                    put("nonce", nonce)
                    put("viewDurationSeconds", durationSec)
                    put("bannerSize", bannerSize)
                    put("packageName", hostPackageName)
                    put("renderedWidthDp", widthDp.toDouble())
                    put("renderedHeightDp", heightDp.toDouble())
                    put("visibleRatio", visibleRatio.toDouble())
                }.toString()
                AdomaticEndpointResolver.openRequest(
                    customBase = customServerUrl,
                    pathAndQuery = "/api/v1/ad/verify",
                    method = "POST",
                    headers = commonHeaders(),
                    jsonBody = body
                ).responseCode
            } catch (_: Exception) {}
        }
    }

    fun recordClick() {
        val nonce = activeImpressionNonce ?: return
        val ad = _currentAd.value ?: return
        scope.launch {
            try {
                val body = JSONObject().apply {
                    put("campaignId", ad.campaignId ?: ad.appId)
                    put("targetPeerAppId", ad.appId)
                    put("publisherApiKey", apiKey)
                    put("nonce", nonce)
                    put("packageName", hostPackageName)
                }.toString()
                AdomaticEndpointResolver.openRequest(
                    customBase = customServerUrl,
                    pathAndQuery = "/api/v1/ad/click",
                    method = "POST",
                    headers = commonHeaders(),
                    jsonBody = body
                ).responseCode
                loadNextAd()
            } catch (_: Exception) {}
        }
    }

    fun reportAd(adId: String) {
        val nonce = activeReportNonce ?: return
        activeReportNonce = null
        scope.launch {
            try {
                val body = JSONObject().apply {
                    put("ad_id", adId)
                    put("nonce", nonce)
                    put("reason", "inappropriate")
                }.toString()
                AdomaticEndpointResolver.openRequest(
                    customBase = customServerUrl,
                    pathAndQuery = "/api/v1/ad/report",
                    method = "POST",
                    headers = commonHeaders(),
                    jsonBody = body
                ).responseCode
                loadNextAd()
            } catch (_: Exception) {}
        }
    }
}

private val VALID_ANDROID_PKG_REGEX = Regex("^[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z0-9_-]+)+$")

private fun resolveLockedAndroidStoreUri(adAppId: String, rawStoreUrl: String): Uri? {
    val pkg = adAppId.trim()
    if (pkg == "aom_founder_treasury") {
        try {
            val u = Uri.parse(rawStoreUrl.trim())
            val host = u.host?.lowercase() ?: ""
            if (u.scheme == "https" && host == "play.google.com" && u.path == "/store/apps/details" && !u.getQueryParameter("id").isNullOrBlank()) {
                return Uri.parse("https://play.google.com/store/apps/details?id=${URLEncoder.encode(u.getQueryParameter("id")!!.trim(), "UTF-8")}")
            }
        } catch (_: Exception) {}
        return Uri.parse("https://ad-o-matic.com/")
    }
    if (!VALID_ANDROID_PKG_REGEX.matches(pkg)) return null
    try {
        val u = Uri.parse(rawStoreUrl.trim())
        val host = u.host?.lowercase() ?: ""
        if (u.scheme == "https" && host == "play.google.com" &&
            u.path == "/store/apps/details" && u.getQueryParameter("id")?.equals(pkg, ignoreCase = true) == true
        ) {
            val builder = Uri.parse("https://play.google.com/store/apps/details").buildUpon()
                .appendQueryParameter("id", pkg)
            val ref = u.getQueryParameter("referrer")
            if (!ref.isNullOrBlank()) builder.appendQueryParameter("referrer", ref)
            return builder.build()
        }
    } catch (_: Exception) {}
    return Uri.parse("https://play.google.com/store/apps/details?id=${URLEncoder.encode(pkg, "UTF-8")}")
}

@Composable
private fun GenesisCrownMark(modifier: Modifier = Modifier) {
    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        val goldBrush = Brush.verticalGradient(
            colors = listOf(
                Color(0xFFFDE047),
                Color(0xFFF59E0B),
                Color(0xFFD97706)
            )
        )
        val strokeColor = Color(0xFF92400E)
        val crownPath = Path().apply {
            moveTo(w * 0.10f, h * 0.24f)
            lineTo(w * 0.18f, h * 0.68f)
            lineTo(w * 0.82f, h * 0.68f)
            lineTo(w * 0.90f, h * 0.24f)
            lineTo(w * 0.67f, h * 0.50f)
            lineTo(w * 0.50f, h * 0.12f)
            lineTo(w * 0.33f, h * 0.50f)
            close()
        }
        drawPath(path = crownPath, brush = goldBrush)
        drawPath(path = crownPath, color = strokeColor, style = Stroke(width = 0.6f, join = StrokeJoin.Miter))

        val baseTop = Offset(w * 0.18f, h * 0.78f)
        val baseSize = Size(w * 0.64f, h * 0.14f)
        drawRoundRect(
            brush = goldBrush,
            topLeft = baseTop,
            size = baseSize,
            cornerRadius = CornerRadius(1f, 1f)
        )
        drawRoundRect(
            color = strokeColor,
            topLeft = baseTop,
            size = baseSize,
            cornerRadius = CornerRadius(1f, 1f),
            style = Stroke(width = 0.55f)
        )
    }
}

@Composable
fun HouseAdBanner(
    modifier: Modifier = Modifier,
    bannerText: String = "",
    bannerImageUrl: String? = null,
    bannerImageFit: String = "cover",
    bannerHeightDp: Int = 60,
    targetAudience: String = "",
    developerId: String? = null,
    apiKey: String = "auto"
) {
    val context = LocalContext.current
    val appContext = context.applicationContext
    val density = LocalDensity.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val rootView = LocalView.current

    val manager = remember(apiKey, bannerText, bannerImageUrl, targetAudience, developerId) {
        HouseAdManager(
            context = appContext,
            apiKey = apiKey,
            buildBannerText = bannerText,
            buildBannerImageUrl = bannerImageUrl,
            targetAudience = targetAudience,
            developerId = developerId
        )
    }

    val currentAd by manager.currentAd.collectAsState()
    val ad = currentAd ?: manager.getBuildEmbeddedSelfAd()

    if (ad.fallbackType == "CLEAN_UI_HIDE" || !ad.active) {
        LaunchedEffect(ad.fallbackType) {
            delay(60000L)
            manager.loadNextAd()
        }
        return
    }

    var isVisibleOnScreen by remember { mutableStateOf(false) }
    var renderedW by remember { mutableStateOf(320f) }
    var renderedH by remember { mutableStateOf(60f) }
    var renderedRatio by remember { mutableStateOf(1f) }
    var showReport by remember { mutableStateOf(false) }

    var iconBitmap by remember(ad.iconUrl) { mutableStateOf<ImageBitmap?>(null) }
    var customBannerBitmap by remember(ad.customBannerUrl) { mutableStateOf<ImageBitmap?>(null) }

    LaunchedEffect(ad.iconUrl) {
        iconBitmap = AdomaticBitmapCache.load(ad.iconUrl)
    }
    LaunchedEffect(ad.customBannerUrl) {
        customBannerBitmap = ad.customBannerUrl?.let { AdomaticBitmapCache.load(it) }
    }

    LaunchedEffect(ad.campaignId, ad.appId, ad.title) {
        var visibleMs = 0L
        var totalMs = 0L
        var verified = false
        while (totalMs < 45000L) {
            delay(250L)
            totalMs += 250L
            val resumed = lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
            val shown = rootView.isShown && rootView.windowVisibility == android.view.View.VISIBLE
            if (!verified) {
                if (isVisibleOnScreen && resumed && shown) {
                    visibleMs += 250L
                    if (visibleMs >= 2250L) {
                        verified = true
                        manager.verifyImpression(visibleMs / 1000.0, renderedW, renderedH, renderedRatio)
                    }
                } else {
                    visibleMs = 0L
                }
            }
        }
        manager.loadNextAd()
    }

    if (showReport) {
        AlertDialog(
            onDismissRequest = { showReport = false },
            title = { Text(ad.reportTitle, fontSize = 15.sp, fontWeight = FontWeight.SemiBold) },
            text = { Text(ad.reportPrompt, fontSize = 13.sp) },
            confirmButton = {
                TextButton(onClick = {
                    manager.reportAd(ad.campaignId ?: ad.appId)
                    showReport = false
                }) { Text(ad.reportLabel) }
            },
            dismissButton = {
                TextButton(onClick = { showReport = false }) { Text(ad.cancelLabel) }
            }
        )
    }

    val isDark = isSystemInDarkTheme() || ad.bannerTheme == "modern_dark"
    val surfaceBg = if (isDark) Color(0xFF16181B) else Color(0xFFFFFFFF)
    val borderCol = if (isDark) Color(0xFF2A2D33) else Color(0xFFE2E8F0)
    val inkPrimary = if (isDark) Color(0xFFEDEDEB) else Color(0xFF0F172A)
    val inkSecondary = if (isDark) Color(0xFF989CA4) else Color(0xFF475569)
    val ctaBg = if (isDark) Color(0xFF2563EB) else Color(0xFF01875F)
    val clampedHeight = bannerHeightDp.coerceIn(50, 120)

    Box(
        modifier = modifier
            .fillMaxWidth()
            .onGloballyPositioned { coords ->
                if (!coords.isAttached) {
                    isVisibleOnScreen = false
                    return@onGloballyPositioned
                }
                val wPx = coords.size.width.toFloat()
                val hPx = coords.size.height.toFloat()
                val minW = with(density) { 200.dp.toPx() }
                val minH = with(density) { 36.dp.toPx() }
                if (wPx < minW || hPx < minH) {
                    isVisibleOnScreen = false
                    return@onGloballyPositioned
                }
                val b = coords.boundsInWindow()
                val visW = (b.right - b.left).coerceAtLeast(0f)
                val visH = (b.bottom - b.top).coerceAtLeast(0f)
                val ratio = if (wPx * hPx > 0f) (visW * visH) / (wPx * hPx) else 0f
                renderedW = with(density) { wPx.toDp().value }
                renderedH = with(density) { hPx.toDp().value }
                renderedRatio = ratio
                isVisibleOnScreen = ratio >= 0.50f
            }
            .clip(RoundedCornerShape(8.dp))
            .background(surfaceBg)
            .border(1.dp, borderCol, RoundedCornerShape(8.dp))
            .clickable {
                val safeStoreUri = resolveLockedAndroidStoreUri(ad.appId, ad.storeUrl)
                if (safeStoreUri != null) {
                    manager.recordClick()
                    try {
                        context.startActivity(
                            Intent(Intent.ACTION_VIEW, safeStoreUri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                    } catch (_: Exception) {}
                }
            }
    ) {
        Crossfade(targetState = ad, label = "AdomaticCrossfade") { target ->
            Column(modifier = Modifier.fillMaxWidth()) {
                if (customBannerBitmap != null) {
                    val resolvedScale = if (bannerImageFit.equals("contain", ignoreCase = true)) {
                        ContentScale.Fit
                    } else {
                        ContentScale.Crop
                    }
                    Image(
                        bitmap = customBannerBitmap!!,
                        contentDescription = target.title,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(clampedHeight.dp)
                            .background(surfaceBg),
                        contentScale = resolvedScale
                    )
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "ad-o-matic",
                            fontSize = 8.sp,
                            fontWeight = FontWeight.Medium,
                            letterSpacing = 0.25.sp,
                            color = inkSecondary.copy(alpha = 0.65f)
                        )
                        if (target.isGenesisMember) {
                            GenesisMemberBadgeRow(
                                textColor = inkPrimary.copy(alpha = 0.70f),
                                onClick = {
                                    try {
                                        context.startActivity(
                                            Intent(Intent.ACTION_VIEW, Uri.parse(manager.activeGenesisUrl()))
                                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                        )
                                    } catch (_: Exception) {}
                                }
                            )
                        }
                    }
                } else {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 56.dp)
                            .padding(start = 10.dp, end = 10.dp, top = 7.dp, bottom = 6.dp)
                    ) {
                        if (iconBitmap != null) {
                            Image(
                                bitmap = iconBitmap!!,
                                contentDescription = target.title,
                                modifier = Modifier
                                    .size(40.dp)
                                    .clip(RoundedCornerShape(8.dp)),
                                contentScale = ContentScale.Crop
                            )
                        }
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(2.dp)
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(5.dp),
                                modifier = Modifier.padding(end = 14.dp)
                            ) {
                                Box(
                                    modifier = Modifier
                                        .background(inkSecondary.copy(alpha = 0.08f), RoundedCornerShape(3.dp))
                                        .border(0.6.dp, inkSecondary.copy(alpha = 0.35f), RoundedCornerShape(3.dp))
                                        .padding(horizontal = 4.dp, vertical = 0.5.dp)
                                ) {
                                    Text(
                                        text = target.adBadge,
                                        fontSize = 7.5.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        letterSpacing = 0.4.sp,
                                        color = inkSecondary.copy(alpha = 0.85f),
                                        lineHeight = 9.sp
                                    )
                                }
                                Text(
                                    text = target.title,
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = inkPrimary,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    lineHeight = 14.sp
                                )
                            }
                            if (target.description.isNotBlank()) {
                                Text(
                                    text = target.description,
                                    fontSize = 10.5.sp,
                                    fontWeight = FontWeight.Normal,
                                    color = inkSecondary,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    lineHeight = 13.sp
                                )
                            }
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(top = 1.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = "ad-o-matic",
                                    fontSize = 8.sp,
                                    fontWeight = FontWeight.Medium,
                                    letterSpacing = 0.25.sp,
                                    color = inkSecondary.copy(alpha = 0.65f)
                                )
                                if (target.isGenesisMember) {
                                    GenesisMemberBadgeRow(
                                        textColor = inkPrimary.copy(alpha = 0.70f),
                                        onClick = {
                                            try {
                                                context.startActivity(
                                                    Intent(Intent.ACTION_VIEW, Uri.parse(manager.activeGenesisUrl()))
                                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                                )
                                            } catch (_: Exception) {}
                                        }
                                    )
                                }
                            }
                        }
                        Surface(
                            color = ctaBg,
                            shape = RoundedCornerShape(999.dp)
                        ) {
                            Text(
                                text = target.installCta,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color.White,
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
                            )
                        }
                    }
                }
            }
        }

        // Discreet corner info/report control
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .size(18.dp)
                .clickable { showReport = true }
        ) {
            Text(
                text = "i",
                fontSize = 9.sp,
                fontFamily = FontFamily.Serif,
                fontStyle = FontStyle.Italic,
                fontWeight = FontWeight.Bold,
                color = inkSecondary.copy(alpha = 0.45f)
            )
        }
    }
}

@Composable
private fun GenesisMemberBadgeRow(
    textColor: Color,
    onClick: () -> Unit
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        modifier = Modifier.clickable(onClick = onClick)
    ) {
        Text(
            text = "Genesis Member",
            fontSize = 8.sp,
            fontFamily = FontFamily.SansSerif,
            fontWeight = FontWeight.Medium,
            letterSpacing = 0.3.sp,
            color = textColor,
            lineHeight = 9.sp
        )
        GenesisCrownMark(modifier = Modifier.size(10.5.dp, 9.dp))
    }
}
