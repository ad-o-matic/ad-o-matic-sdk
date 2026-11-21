import React, { useEffect, useRef, useState } from 'react';
import {
  Alert,
  Image,
  Linking,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  useColorScheme,
  View,
} from 'react-native';

/**
 * Ad-o-matic Zero-Dependency Single-File React Native SDK (v5.9)
 *
 * Official HTTPS Endpoint: https://ad-o-matic.com
 *
 * Usage (1 line, zero extra npm packages required):
 *   <HouseAdBanner
 *     appId="com.company.myapp"
 *     bannerText="Chromatic tuner & chord library for guitarists"
 *     targetAudience="guitarists, musicians, songwriting, 18-44"
 *   />
 */

export interface HouseAdBannerProps {
  appId: string;
  bannerText?: string;
  bannerImageUrl?: string;
  bannerImageFit?: 'cover' | 'contain';
  bannerHeight?: number;
  targetAudience?: string;
  developerId?: string;
}

interface AdModel {
  campaignId?: string;
  appId: string;
  title: string;
  description: string;
  iconUrl: string;
  customBannerUrl?: string | null;
  storeUrl: string;
  bannerTheme?: string;
  isGenesisMember?: boolean;
  active?: boolean;
}

interface UiStringsModel {
  adBadge: string;
  installCta: string;
  reportTitle: string;
  reportPrompt: string;
  cancelBtn: string;
  confirmReportBtn: string;
}

const BASE_URL = 'https://ad-o-matic.com';

function resolveLockedStoreUrl(adAppId: string, rawUrl: string): string | null {
  const pkg = String(adAppId || '').trim();
  const trimmed = String(rawUrl || '').trim();
  if (pkg === 'aom_founder_treasury') {
    if (
      /^https:\/\/play\.google\.com\/store\/apps\/details\?/.test(trimmed) ||
      /^https:\/\/apps\.apple\.com\/([a-z]{2}\/)?app\//i.test(trimmed)
    ) {
      return trimmed;
    }
    return `${BASE_URL}/`;
  }
  if (!trimmed.startsWith('https://')) return null;
  if (Platform.OS === 'ios') {
    if (/^https:\/\/apps\.apple\.com\/([a-z]{2}\/)?app\//i.test(trimmed)) return trimmed;
    return null;
  }
  if (/^https:\/\/play\.google\.com\/store\/apps\/details\?/.test(trimmed)) return trimmed;
  return null;
}

async function fetchAdomatic(path: string, init?: RequestInit): Promise<any | null> {
  try {
    const res = await fetch(`${BASE_URL}${path}`, {
      ...init,
      headers: { Accept: 'application/json', ...(init?.headers || {}) },
    });
    if (res.ok) return await res.json();
  } catch {
    // Ignore transient offline errors
  }
  return null;
}

export const HouseAdBanner: React.FC<HouseAdBannerProps> = ({
  appId,
  bannerText = '',
  bannerImageUrl,
  bannerImageFit = 'cover',
  bannerHeight = 60,
  targetAudience = '',
  developerId,
}) => {
  const colorScheme = useColorScheme();
  const clampedHeight = Math.min(120, Math.max(50, bannerHeight));
  const [ad, setAd] = useState<AdModel>({
    appId,
    title: appId,
    description: bannerText.trim() || '',
    iconUrl: '',
    customBannerUrl: bannerImageUrl?.trim() || null,
    storeUrl:
      Platform.OS === 'ios'
        ? 'https://apps.apple.com'
        : `https://play.google.com/store/apps/details?id=${encodeURIComponent(appId)}`,
    isGenesisMember: false,
    active: true,
  });
  const [ui, setUi] = useState<UiStringsModel>({
    adBadge: 'AD',
    installCta: 'Install',
    reportTitle: 'Report Ad',
    reportPrompt: 'Report this ad for inappropriate content or a broken link?',
    cancelBtn: 'Cancel',
    confirmReportBtn: 'Report',
  });

  const nonceRef = useRef<string | null>(null);
  const clickNonceRef = useRef<string | null>(null);
  const reportNonceRef = useRef<string | null>(null);
  const lastCampaignIdRef = useRef<string | null>(null);
  const mountedRef = useRef(true);

  const loadAd = async () => {
    const qs = new URLSearchParams({
      apiKey: 'auto',
      packageName: appId,
      platform: Platform.OS === 'ios' ? 'ios' : 'android',
      bannerSize: '320x50',
      buildBannerText: bannerText.trim(),
      buildBannerImage: (bannerImageUrl || '').trim(),
      targetAudience: targetAudience.trim(),
      isDebugBuild: typeof __DEV__ !== 'undefined' && __DEV__ ? '1' : '0',
    });
    if (developerId?.trim()) qs.set('developerId', developerId.trim());
    if (lastCampaignIdRef.current) qs.set('excludeCampaignId', lastCampaignIdRef.current);

    const data = await fetchAdomatic(`/api/v1/ad/request?${qs.toString()}`);
    if (!mountedRef.current || !data) return;

    if (data.uiStrings && typeof data.uiStrings === 'object') {
      setUi((prev) => ({
        adBadge: data.uiStrings.adBadge || prev.adBadge,
        installCta: data.uiStrings.installCta || prev.installCta,
        reportTitle: data.uiStrings.reportTitle || prev.reportTitle,
        reportPrompt: data.uiStrings.reportPrompt || prev.reportPrompt,
        cancelBtn: data.uiStrings.cancelBtn || prev.cancelBtn,
        confirmReportBtn: data.uiStrings.confirmReportBtn || prev.confirmReportBtn,
      }));
    }

    if (data.capReached || data.hideSlot) {
      setAd((prev) => ({ ...prev, active: false }));
      return;
    }

    if (!data.ad) return;

    nonceRef.current = data.nonce || null;
    clickNonceRef.current = data.nonce || null;
    reportNonceRef.current = data.nonce || null;
    if (data.ad.campaignId) lastCampaignIdRef.current = data.ad.campaignId;
    setAd({ ...data.ad, active: true });

    if (data.nonce) {
      const issuedNonce = data.nonce;
      setTimeout(() => {
        if (!mountedRef.current || nonceRef.current !== issuedNonce) return;
        nonceRef.current = null;
        fetchAdomatic('/api/v1/ad/verify', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-App-Package': appId,
            'X-App-Debug-Build': typeof __DEV__ !== 'undefined' && __DEV__ ? '1' : '0',
          },
          body: JSON.stringify({
            apiKey: 'auto',
            packageName: appId,
            nonce: issuedNonce,
            viewDurationSeconds: 2.2,
            renderedWidthDp: 340,
            renderedHeightDp: 68,
            visibleRatio: 1.0,
          }),
        });
      }, 2250);
    }
  };

  useEffect(() => {
    mountedRef.current = true;
    loadAd();
    const interval = setInterval(loadAd, 45000);
    return () => {
      mountedRef.current = false;
      clearInterval(interval);
    };
  }, [appId, bannerText, bannerImageUrl, targetAudience, developerId]);

  if (ad.active === false) return null;

  const isDark = colorScheme === 'dark' || ad.bannerTheme === 'modern_dark';
  const surfaceBg = isDark ? '#16181B' : '#FFFFFF';
  const borderCol = isDark ? '#2A2D33' : '#E2E8F0';
  const inkPrimary = isDark ? '#EDEDEB' : '#0F172A';
  const inkSecondary = isDark ? '#989CA4' : '#475569';
  const ctaBg = isDark ? '#2563EB' : '#01875F';

  const handlePress = () => {
    const target = resolveLockedStoreUrl(ad.appId, ad.storeUrl);
    if (!target) return;
    if (clickNonceRef.current) {
      const cn = clickNonceRef.current;
      clickNonceRef.current = null;
      fetchAdomatic('/api/v1/ad/click', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          campaignId: ad.campaignId || ad.appId,
          targetPeerAppId: ad.appId,
          publisherApiKey: 'auto',
          nonce: cn,
          packageName: appId,
        }),
      });
    }
    Linking.openURL(target).catch(() => {});
  };

  const handleReport = () => {
    Alert.alert(ui.reportTitle, ui.reportPrompt, [
      { text: ui.cancelBtn, style: 'cancel' },
      {
        text: ui.confirmReportBtn,
        style: 'destructive',
        onPress: async () => {
          const rn = reportNonceRef.current;
          if (!rn) return;
          reportNonceRef.current = null;
          await fetchAdomatic('/api/v1/ad/report', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              ad_id: ad.campaignId || ad.appId,
              nonce: rn,
              reason: 'inappropriate',
            }),
          });
          loadAd();
        },
      },
    ]);
  };

  const customUrl = (ad.customBannerUrl || '').trim();
  const hasCustomImage = customUrl.startsWith('https://');

  return (
    <View style={[styles.card, { backgroundColor: surfaceBg, borderColor: borderCol }]}>
      <Pressable
        onPress={handlePress}
        accessibilityLabel={`Sponsored app: ${ad.title}`}
      >
        {hasCustomImage ? (
          <View>
            <Image
              source={{ uri: customUrl }}
              style={[styles.customImg, { height: clampedHeight, backgroundColor: surfaceBg }]}
              resizeMode={bannerImageFit === 'contain' ? 'contain' : 'cover'}
            />
            <View style={styles.customFooterWrap}>
              <Text style={[styles.footerText, { color: inkSecondary }]}>ad-o-matic</Text>
              {ad.isGenesisMember ? (
                <Text style={[styles.genesisText, { color: inkPrimary }]}>Genesis Member</Text>
              ) : null}
            </View>
          </View>
        ) : (
          <View style={styles.bodyRow}>
            {ad.iconUrl?.startsWith('https://') ? (
              <Image source={{ uri: ad.iconUrl }} style={styles.icon} resizeMode="cover" />
            ) : null}
            <View style={styles.textCol}>
              <View style={styles.titleRow}>
                <View
                  style={[
                    styles.adPill,
                    {
                      borderColor: isDark ? 'rgba(152,156,164,0.35)' : 'rgba(71,85,105,0.35)',
                      backgroundColor: isDark ? 'rgba(152,156,164,0.10)' : 'rgba(71,85,105,0.06)',
                    },
                  ]}
                >
                  <Text style={[styles.adPillText, { color: inkSecondary }]}>{ui.adBadge}</Text>
                </View>
                <Text style={[styles.title, { color: inkPrimary }]} numberOfLines={1}>
                  {ad.title}
                </Text>
              </View>
              {ad.description ? (
                <Text style={[styles.desc, { color: inkSecondary }]} numberOfLines={1}>
                  {ad.description}
                </Text>
              ) : null}
              <View style={styles.footerRow}>
                <Text style={[styles.footerText, { color: inkSecondary }]}>ad-o-matic</Text>
                {ad.isGenesisMember ? (
                  <Text style={[styles.genesisText, { color: inkPrimary }]}>Genesis Member</Text>
                ) : null}
              </View>
            </View>
            <View style={[styles.ctaBtn, { backgroundColor: ctaBg }]}>
              <Text style={styles.ctaText}>{ui.installCta}</Text>
            </View>
          </View>
        )}
      </Pressable>

      <Pressable onPress={handleReport} hitSlop={8} style={styles.reportBtn}>
        <Text style={[styles.reportText, { color: inkSecondary }]}>i</Text>
      </Pressable>
    </View>
  );
};

const styles = StyleSheet.create({
  card: {
    borderRadius: 8,
    borderWidth: 1,
    overflow: 'hidden',
    position: 'relative',
  },
  customImg: { width: '100%' },
  customFooterWrap: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 3,
  },
  bodyRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 10,
    paddingVertical: 7,
    gap: 10,
    minHeight: 56,
  },
  icon: { width: 38, height: 38, borderRadius: 8 },
  textCol: { flex: 1, minWidth: 0, gap: 2 },
  titleRow: { flexDirection: 'row', alignItems: 'center', gap: 5, paddingRight: 14 },
  adPill: { borderWidth: 0.6, borderRadius: 3, paddingHorizontal: 4, paddingVertical: 0.5 },
  adPillText: { fontSize: 7.5, fontWeight: '600', letterSpacing: 0.4 },
  title: { fontSize: 12, fontWeight: '600', flex: 1 },
  desc: { fontSize: 10.5 },
  ctaBtn: {
    paddingHorizontal: 10,
    paddingVertical: 4.5,
    borderRadius: 999,
  },
  ctaText: { color: '#FFFFFF', fontSize: 10, fontWeight: '600' },
  footerRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginTop: 1,
  },
  footerText: { fontSize: 8, fontWeight: '500', opacity: 0.55 },
  genesisText: { fontSize: 8, fontWeight: '500', opacity: 0.68 },
  reportBtn: {
    position: 'absolute',
    top: 3,
    right: 5,
    paddingHorizontal: 4,
    paddingVertical: 1,
  },
  reportText: { fontSize: 9, fontStyle: 'italic', fontWeight: '700', opacity: 0.45 },
});
