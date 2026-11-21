// Official Ad-o-matic Single-File Zero-Dependency Flutter SDK (https://ad-o-matic.com/sdk/HouseAdBanner.dart)
// Supports Android & iOS Flutter apps with zero external pubspec.yaml dependencies.
//
// 1-Line Usage:
//   HouseAdBanner(
//     packageName: 'com.company.app',
//     bannerText: 'Short benefit-driven description of your app',
//     targetAudience: 'describe who this app is built for, 25-44',
//   )

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class HouseAdData {
  final String? campaignId;
  final String appId;
  final String title;
  final String description;
  final String iconUrl;
  final String storeUrl;
  final String? customBannerUrl;
  final String bannerSize;
  final String bannerTheme;
  final String fallbackType;
  final bool active;
  final bool isGenesisMember;

  const HouseAdData({
    this.campaignId,
    required this.appId,
    required this.title,
    required this.description,
    required this.iconUrl,
    required this.storeUrl,
    this.customBannerUrl,
    this.bannerSize = '320x50',
    this.bannerTheme = 'modern_clean',
    this.fallbackType = 'NONE',
    this.active = true,
    this.isGenesisMember = false,
  });
}

class HouseAdBanner extends StatefulWidget {
  final String packageName;
  final String appTitle;
  final String bannerText;
  final String? bannerImageUrl;
  final String bannerImageFit;
  final double bannerHeight;
  final String targetAudience;
  final String? lang;
  final String apiKey;
  final String? developerId;
  final FutureOr<void> Function(Uri storeUri)? onOpenStore;

  const HouseAdBanner({
    super.key,
    this.packageName = '',
    this.appTitle = '',
    this.bannerText = '',
    this.bannerImageUrl,
    this.bannerImageFit = 'cover',
    this.bannerHeight = 60.0,
    this.targetAudience = '',
    this.lang,
    this.apiKey = 'auto',
    this.developerId,
    this.onOpenStore,
  });

  /// Immutable Anti-Scam Store Link Lock: opens ONLY official Google Play or Apple App Store pages.
  static Uri? resolveLockedStoreUri({
    required String adAppId,
    required String rawStoreUrl,
    required bool isIos,
  }) {
    final pkg = adAppId.trim();
    if (pkg == 'aom_founder_treasury') {
      try {
        final u = Uri.parse(rawStoreUrl.trim());
        if (u.scheme == 'https' &&
            (u.host == 'play.google.com' || u.host == 'apps.apple.com')) {
          return u;
        }
      } catch (_) {}
      return Uri.parse('https://ad-o-matic.com/');
    }

    if (isIos) {
      try {
        final u = Uri.parse(rawStoreUrl.trim());
        if (u.scheme == 'https' &&
            u.host.toLowerCase() == 'apps.apple.com' &&
            u.path.startsWith('/app/')) {
          return u;
        }
      } catch (_) {}
      return Uri.parse('https://ad-o-matic.com/');
    }

    final validPkg =
        RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_-]+)+$').hasMatch(pkg);
    if (!validPkg) return null;

    try {
      final u = Uri.parse(rawStoreUrl.trim());
      if (u.scheme == 'https' &&
          u.host.toLowerCase() == 'play.google.com' &&
          u.path == '/store/apps/details' &&
          u.queryParameters['id']?.toLowerCase() == pkg.toLowerCase()) {
        return Uri.https('play.google.com', '/store/apps/details', {
          'id': pkg,
          if (u.queryParameters['referrer'] != null)
            'referrer': u.queryParameters['referrer']!,
        });
      }
    } catch (_) {}

    return Uri.https('play.google.com', '/store/apps/details', {'id': pkg});
  }

  @override
  State<HouseAdBanner> createState() => _HouseAdBannerState();
}

class _HouseAdBannerState extends State<HouseAdBanner>
    with WidgetsBindingObserver {
  static const String _primaryBase = 'https://ad-o-matic.com';

  HouseAdData? _currentAd;
  String? _currentNonce;
  String? _activeImpressionNonce;
  String? _activeReportNonce;
  String? _lastCampaignId;
  Timer? _visibilityTick;
  int _visibleAccumMs = 0;
  int _rotationAccumMs = 0;
  bool _verifiedCurrentAd = false;
  bool _appResumed = true;

  String _adBadgeLabel = 'AD';
  String _reportTitle = 'Report Ad';
  String _reportPrompt =
      'Report this ad for inappropriate content or a broken link?';
  String _cancelLabel = 'Cancel';
  String _reportConfirmLabel = 'Report';

  bool get _isIos => !kIsWeb && Platform.isIOS;

  String get _effectivePackage =>
      widget.packageName.trim().isNotEmpty ? widget.packageName.trim() : 'auto';

  String get _effectiveTitle =>
      widget.appTitle.trim().isNotEmpty ? widget.appTitle.trim() : 'App';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final customImg = widget.bannerImageUrl?.trim();
    _currentAd = HouseAdData(
      appId: _effectivePackage,
      title: _effectiveTitle,
      description: widget.bannerText.trim().isNotEmpty
          ? widget.bannerText.trim()
          : 'Discover $_effectiveTitle',
      iconUrl: '',
      storeUrl: _isIos
          ? 'https://apps.apple.com'
          : 'https://play.google.com/store/apps/details?id=$_effectivePackage',
      customBannerUrl:
          (customImg != null && customImg.isNotEmpty) ? customImg : null,
      isGenesisMember: false,
    );
    _loadNextAd();
    _startViewabilityAndRotationLoop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
  }

  String _resolveLangCode() {
    final explicit = (widget.lang ?? '').trim().toLowerCase();
    if (explicit.length >= 2) return explicit.substring(0, 2);
    return WidgetsBinding.instance.platformDispatcher.locale.languageCode
        .toLowerCase();
  }

  Map<String, String> _commonHeaders() => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-App-Package': _effectivePackage,
        'X-App-Debug-Build': kDebugMode ? '1' : '0',
        if (widget.targetAudience.trim().isNotEmpty)
          'X-Target-Audience': widget.targetAudience.trim(),
        if ((widget.developerId ?? '').trim().isNotEmpty)
          'X-Developer-Id': widget.developerId!.trim(),
      };

  Future<String?> _requestJson({
    required String pathAndQuery,
    required String method,
    String? jsonBody,
  }) async {
    if (kIsWeb) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final uri = Uri.parse('$_primaryBase$pathAndQuery');
      final req = method == 'POST'
          ? await client.postUrl(uri)
          : await client.getUrl(uri);
      _commonHeaders().forEach(req.headers.set);
      if (method == 'POST' && jsonBody != null) {
        final bytes = utf8.encode(jsonBody);
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final resp = await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        return await resp.transform(utf8.decoder).join();
      }
    } catch (_) {
    } finally {
      client.close(force: true);
    }
    return null;
  }

  Future<void> _loadNextAd() async {
    final platformParam = _isIos ? 'ios' : 'android';
    final dbgFlag = kDebugMode ? '1' : '0';
    final langCode = _resolveLangCode();
    final qs = Uri(queryParameters: {
      'apiKey': widget.apiKey,
      'packageName': _effectivePackage,
      'appTitle': _effectiveTitle,
      'buildBannerText': widget.bannerText.trim(),
      if ((widget.bannerImageUrl ?? '').trim().isNotEmpty)
        'buildBannerImage': widget.bannerImageUrl!.trim(),
      'platform': platformParam,
      'lang': langCode,
      'isDebugBuild': dbgFlag,
      if (_lastCampaignId != null && _lastCampaignId!.isNotEmpty)
        'excludeCampaignId': _lastCampaignId!,
      if (widget.targetAudience.trim().isNotEmpty)
        'targetAudience': widget.targetAudience.trim(),
      if ((widget.developerId ?? '').trim().isNotEmpty)
        'developerId': widget.developerId!.trim(),
    }).query;

    final bodyStr = await _requestJson(
      pathAndQuery: '/api/v1/ad/request?$qs',
      method: 'GET',
    );
    if (!mounted || bodyStr == null) return;

    try {
      final json = jsonDecode(bodyStr) as Map<String, dynamic>;
      final fallbackType = (json['fallbackType'] as String?) ?? 'NONE';
      final adObj = json['ad'] as Map<String, dynamic>?;
      final nonce = json['nonce'] as String?;
      final uiMap = json['uiStrings'] as Map<String, dynamic>?;

      if (uiMap != null) {
        _adBadgeLabel =
            (uiMap['adBadge'] as String?)?.trim().isNotEmpty == true
                ? (uiMap['adBadge'] as String).trim()
                : _adBadgeLabel;
        _reportTitle =
            (uiMap['reportTitle'] as String?)?.trim().isNotEmpty == true
                ? (uiMap['reportTitle'] as String).trim()
                : _reportTitle;
        _reportPrompt =
            (uiMap['reportPrompt'] as String?)?.trim().isNotEmpty == true
                ? (uiMap['reportPrompt'] as String).trim()
                : _reportPrompt;
        _cancelLabel =
            (uiMap['cancelBtn'] as String?)?.trim().isNotEmpty == true
                ? (uiMap['cancelBtn'] as String).trim()
                : _cancelLabel;
        _reportConfirmLabel =
            (uiMap['confirmReportBtn'] as String?)?.trim().isNotEmpty == true
                ? (uiMap['confirmReportBtn'] as String).trim()
                : _reportConfirmLabel;
      }

      if (json['capReached'] == true || json['hideSlot'] == true) {
        setState(() {
          _currentAd = HouseAdData(
            appId: _effectivePackage,
            title: '',
            description: '',
            iconUrl: '',
            storeUrl: '',
            fallbackType: fallbackType,
            active: false,
          );
        });
        return;
      }

      if (adObj != null) {
        _currentNonce = (nonce != null && nonce.isNotEmpty) ? nonce : null;
        _activeImpressionNonce = _currentNonce;
        _activeReportNonce = _currentNonce;
        _visibleAccumMs = 0;
        _rotationAccumMs = 0;
        _verifiedCurrentAd = false;
        final cid = adObj['campaignId'] as String?;
        if (cid != null && cid.isNotEmpty) _lastCampaignId = cid;

        setState(() {
          _currentAd = HouseAdData(
            campaignId: cid,
            appId: (adObj['appId'] as String?) ?? _effectivePackage,
            title: (adObj['title'] as String?) ?? _effectiveTitle,
            description:
                (adObj['description'] as String?) ?? widget.bannerText.trim(),
            iconUrl: (adObj['iconUrl'] as String?) ?? '',
            storeUrl: (adObj['storeUrl'] as String?) ??
                (_isIos
                    ? 'https://apps.apple.com'
                    : 'https://play.google.com/store/apps/details?id=$_effectivePackage'),
            customBannerUrl: adObj['customBannerUrl'] as String?,
            bannerSize: (adObj['bannerSize'] as String?) ?? '320x50',
            bannerTheme: (adObj['bannerTheme'] as String?) ?? 'modern_clean',
            fallbackType: fallbackType,
            active: true,
            isGenesisMember: (adObj['isGenesisMember'] as bool?) ?? false,
          );
        });
      }
    } catch (_) {}
  }

  void _startViewabilityAndRotationLoop() {
    _visibilityTick?.cancel();
    final rotationIntervalMs = kDebugMode ? 10000 : 45000;
    _visibilityTick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      _rotationAccumMs += 500;
      if (_appResumed && !_verifiedCurrentAd && _currentAd?.active == true) {
        _visibleAccumMs += 500;
        if (_visibleAccumMs >= 2500) {
          _verifiedCurrentAd = true;
          _verifyImpression(_visibleAccumMs / 1000.0);
        }
      }
      if (_rotationAccumMs >= rotationIntervalMs) {
        _rotationAccumMs = 0;
        _loadNextAd();
      }
    });
  }

  Future<void> _verifyImpression(double durationSec) async {
    final nonce = _currentNonce;
    if (nonce == null) return;
    _currentNonce = null;
    final body = jsonEncode({
      'apiKey': widget.apiKey,
      'nonce': nonce,
      'viewDurationSeconds': durationSec,
      'bannerSize': _currentAd?.bannerSize ?? '320x50',
      'packageName': _effectivePackage,
      'renderedWidthDp': 340.0,
      'renderedHeightDp': 60.0,
      'visibleRatio': 1.0,
    });
    await _requestJson(
      pathAndQuery: '/api/v1/ad/verify',
      method: 'POST',
      jsonBody: body,
    );
  }

  Future<void> _handleTap(HouseAdData ad) async {
    final safeUri = HouseAdBanner.resolveLockedStoreUri(
      adAppId: ad.appId,
      rawStoreUrl: ad.storeUrl,
      isIos: _isIos,
    );
    if (safeUri == null) return;

    final cn = _activeImpressionNonce;
    _activeImpressionNonce = null;
    if (cn != null) {
      final body = jsonEncode({
        'campaignId': ad.campaignId ?? ad.appId,
        'targetPeerAppId': ad.appId,
        'publisherApiKey': widget.apiKey,
        'nonce': cn,
        'packageName': _effectivePackage,
      });
      unawaited(
        _requestJson(
          pathAndQuery: '/api/v1/ad/click',
          method: 'POST',
          jsonBody: body,
        ),
      );
    }

    if (widget.onOpenStore != null) {
      await widget.onOpenStore!(safeUri);
    }
  }

  Future<void> _reportCurrentAd(HouseAdData ad) async {
    final rn = _activeReportNonce;
    if (rn == null) return;
    _activeReportNonce = null;
    final body = jsonEncode({
      'ad_id': ad.campaignId ?? ad.appId,
      'nonce': rn,
      'reason': 'inappropriate',
    });
    await _requestJson(
      pathAndQuery: '/api/v1/ad/report',
      method: 'POST',
      jsonBody: body,
    );
    if (mounted) {
      _loadNextAd();
    }
  }

  Future<void> _showReportDialog(HouseAdData ad) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_reportTitle),
        content: Text(_reportPrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(_cancelLabel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _reportCurrentAd(ad);
            },
            child: Text(_reportConfirmLabel),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _visibilityTick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _currentAd;
    if (ad == null || !ad.active || ad.fallbackType == 'CLEAN_UI_HIDE') {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark ||
        ad.bannerTheme == 'modern_dark';
    final bannerBg = isDark ? const Color(0xFF16181B) : const Color(0xFFFFFFFF);
    final borderCol =
        isDark ? const Color(0xFF2A2D33) : const Color(0xFFE2E8F0);
    final inkPrimary =
        isDark ? const Color(0xFFEDEDEB) : const Color(0xFF0F172A);
    final inkSecondary =
        isDark ? const Color(0xFF989CA4) : const Color(0xFF475569);

    final customBanner = (ad.customBannerUrl ?? '').trim();
    final hasCustomImage = customBanner.startsWith('https://');
    final clampedHeight = widget.bannerHeight.clamp(50.0, 120.0);

    return Material(
      color: bannerBg,
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _handleTap(ad),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: borderCol, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasCustomImage
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: clampedHeight,
                          child: Image.network(
                            customBanner,
                            fit: widget.bannerImageFit.toLowerCase() ==
                                    'contain'
                                ? BoxFit.contain
                                : BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: _buildFooterRow(ad, inkPrimary, inkSecondary),
                        ),
                      ],
                    )
                  : Container(
                      height: 68,
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 5),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1D2024)
                                  : const Color(0xFFF1F5F9),
                              border: Border.all(color: borderCol),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ad.iconUrl.startsWith('https://')
                                ? Image.network(
                                    ad.iconUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Icon(
                                      Icons.apps_sharp,
                                      size: 18,
                                      color: inkSecondary.withAlpha(178),
                                    ),
                                  )
                                : Icon(
                                    Icons.apps_sharp,
                                    size: 18,
                                    color: inkSecondary.withAlpha(178),
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 16),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 0.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: inkSecondary.withAlpha(20),
                                          border: Border.all(
                                            color: inkSecondary.withAlpha(90),
                                            width: 0.7,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                        child: Text(
                                          _adBadgeLabel,
                                          style: TextStyle(
                                            fontSize: 7.5,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.4,
                                            height: 1.1,
                                            color: inkSecondary.withAlpha(215),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          ad.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.0,
                                            fontWeight: FontWeight.w600,
                                            height: 1.15,
                                            color: inkPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  ad.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.6,
                                    height: 1.2,
                                    color: inkSecondary,
                                  ),
                                ),
                                _buildFooterRow(ad, inkPrimary, inkSecondary),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _showReportDialog(ad),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.info_outline,
                  size: 12,
                  color: inkSecondary.withAlpha(108),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterRow(
    HouseAdData ad,
    Color inkPrimary,
    Color inkSecondary,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'ad-o-matic',
          style: TextStyle(
            fontSize: 8.0,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.25,
            height: 1.1,
            color: inkSecondary.withAlpha(140),
          ),
        ),
        if (ad.isGenesisMember)
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Genesis Member',
                style: TextStyle(
                  fontFamily: 'Science Gothic',
                  fontFamilyFallback: const [
                    'Science Gothic',
                    'Orbitron',
                    'Rajdhani',
                    'Eurostile',
                    'sans-serif',
                  ],
                  fontSize: 8.2,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.35,
                  height: 1.0,
                  color: inkPrimary.withAlpha(175),
                ),
              ),
              const SizedBox(width: 3),
              const CustomPaint(
                size: Size(10.5, 9.0),
                painter: _GenesisCrownPainter(),
              ),
            ],
          ),
      ],
    );
  }
}

class _GenesisCrownPainter extends CustomPainter {
  const _GenesisCrownPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final goldGradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFFDE047),
        Color(0xFFF59E0B),
        Color(0xFFD97706),
      ],
    ).createShader(rect);

    final fillPaint = Paint()
      ..shader = goldGradient
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final strokePaint = Paint()
      ..color = const Color(0xFF92400E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.45
      ..strokeJoin = StrokeJoin.miter
      ..isAntiAlias = true;

    // Clean, sharp 3-peak crown without balls on the tips
    final crownPath = Path()
      ..moveTo(size.width * 0.10, size.height * 0.24)
      ..lineTo(size.width * 0.18, size.height * 0.68)
      ..lineTo(size.width * 0.82, size.height * 0.68)
      ..lineTo(size.width * 0.90, size.height * 0.24)
      ..lineTo(size.width * 0.67, size.height * 0.50)
      ..lineTo(size.width * 0.50, size.height * 0.12)
      ..lineTo(size.width * 0.33, size.height * 0.50)
      ..close();

    canvas.drawPath(crownPath, fillPaint);
    canvas.drawPath(crownPath, strokePaint);

    // Distinct royal base bar separated by a clean gap
    final baseRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.18,
        size.height * 0.78,
        size.width * 0.64,
        size.height * 0.14,
      ),
      const Radius.circular(0.5),
    );
    canvas.drawRRect(baseRect, fillPaint);
    canvas.drawRRect(baseRect, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
