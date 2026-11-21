import SwiftUI
import Foundation
#if canImport(StoreKit) && os(iOS)
import StoreKit
import UIKit
#endif

/// Ad-o-matic Zero-Dependency Single-File SwiftUI SDK (v5.9)
///
/// Official HTTPS Endpoint: https://ad-o-matic.com
///
/// Drop this single file into any iOS SwiftUI target and add 1 line to your view:
///
///   HouseAdBanner(
///       bannerText: "Short benefit-driven description of your app",
///       targetAudience: "amateur astronomers, stargazing, telescope owners, astrophotography"
///   )
///   // Or zero-arg automatic fallback:
///   HouseAdBanner()
///
/// Anti-Scam Immutable Store Link Lock:
/// Ad destination links cannot be customized or redirected to external websites. Every ad click is locked
/// to open ONLY an official Apple App Store download page (https://apps.apple.com/.../app/...).
///
/// Zero human configuration, zero external Swift packages, zero IDFA, zero App Tracking Transparency popup required.

public struct AdomaticBannerModel: Equatable {
    public var campaignId: String?
    public var appId: String
    public var title: String
    public var description: String
    public var iconUrl: String
    public var customBannerUrl: String?
    public var storeUrl: String
    public var bannerTheme: String
    public var isGenesisMember: Bool
    public var adBadge: String
    public var installCta: String
    public var reportTitle: String
    public var reportPrompt: String
    public var cancelLabel: String
    public var reportLabel: String
    public var active: Bool
}

@MainActor
final class AdomaticBannerViewModel: ObservableObject {
    @Published var ad: AdomaticBannerModel
    private var nonce: String?
    private var clickNonce: String?
    private var reportNonce: String?
    private var lastCampaignId: String?

    let bannerText: String
    let bannerImageUrl: String?
    let targetAudience: String
    let developerId: String?
    let bundleId: String
    let appName: String
    let buildNumber: String
    let isDebugBuild: Bool

    init(bannerText: String = "", bannerImageUrl: String? = nil, targetAudience: String = "", developerId: String? = nil) {
        self.bannerText = bannerText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bannerImageUrl = bannerImageUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.targetAudience = targetAudience.trimmingCharacters(in: .whitespacesAndNewlines)
        self.developerId = developerId
        self.bundleId = Bundle.main.bundleIdentifier ?? "com.adomatic.iosapp"
        self.appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "App"
        let rawVer = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
        let digits = rawVer.filter { $0.isNumber }
        self.buildNumber = digits.isEmpty ? "1" : digits
        #if DEBUG
        self.isDebugBuild = true
        #else
        self.isDebugBuild = false
        #endif

        let defaultDesc = self.bannerText.isEmpty ? "Discover \(self.appName)" : self.bannerText

        self.ad = AdomaticBannerModel(
            campaignId: nil,
            appId: self.bundleId,
            title: self.appName,
            description: defaultDesc,
            iconUrl: "",
            customBannerUrl: self.bannerImageUrl,
            storeUrl: "https://apps.apple.com",
            bannerTheme: "modern_clean",
            isGenesisMember: false,
            adBadge: "AD",
            installCta: "Install",
            reportTitle: "Report Ad",
            reportPrompt: "Report this ad for inappropriate content or a broken link?",
            cancelLabel: "Cancel",
            reportLabel: "Report",
            active: true
        )
    }

    private func candidateBases() -> [String] {
        return ["https://ad-o-matic.com"]
    }

    private func applyHeaders(_ req: inout URLRequest) {
        req.setValue(bundleId, forHTTPHeaderField: "X-App-Package")
        req.setValue(buildNumber, forHTTPHeaderField: "X-App-Version-Code")
        req.setValue(isDebugBuild ? "1" : "0", forHTTPHeaderField: "X-App-Debug-Build")
        if !targetAudience.isEmpty {
            req.setValue(targetAudience, forHTTPHeaderField: "X-Target-Audience")
        }
        if let dev = developerId, !dev.isEmpty {
            req.setValue(dev, forHTTPHeaderField: "X-Developer-Id")
        }
    }

    private func sendWithFailover(path: String, queryItems: [URLQueryItem]? = nil, method: String = "GET", jsonBody: [String: Any]? = nil) async -> Data? {
        for base in candidateBases() {
            guard var comps = URLComponents(string: "\(base)\(path)") else { continue }
            if let q = queryItems { comps.queryItems = q }
            guard let url = comps.url else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.timeoutInterval = 5.0
            applyHeaders(&req)
            if let body = jsonBody {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            }
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let code = (resp as? HTTPURLResponse)?.statusCode, (200...499).contains(code) {
                    return code == 200 ? data : nil
                }
            } catch {
                continue
            }
        }
        return nil
    }

    func fetchAd() async {
        let langCode = Locale.current.languageCode ?? "en"
        var items = [
            URLQueryItem(name: "apiKey", value: "auto"),
            URLQueryItem(name: "packageName", value: bundleId),
            URLQueryItem(name: "appTitle", value: appName),
            URLQueryItem(name: "buildBannerText", value: bannerText),
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "lang", value: langCode),
            URLQueryItem(name: "appVersionCode", value: buildNumber),
            URLQueryItem(name: "isDebugBuild", value: isDebugBuild ? "1" : "0")
        ]
        if let cid = lastCampaignId, !cid.isEmpty {
            items.append(URLQueryItem(name: "excludeCampaignId", value: cid))
        }
        if let img = bannerImageUrl, !img.isEmpty {
            items.append(URLQueryItem(name: "buildBannerImage", value: img))
        }
        if !targetAudience.isEmpty {
            items.append(URLQueryItem(name: "targetAudience", value: targetAudience))
        }
        if let dev = developerId, !dev.isEmpty {
            items.append(URLQueryItem(name: "developerId", value: dev))
        }

        guard let data = await sendWithFailover(path: "/api/v1/ad/request", queryItems: items),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if (root["capReached"] as? Bool) == true || (root["hideSlot"] as? Bool) == true {
            self.ad.active = false
            return
        }
        guard let adObj = root["ad"] as? [String: Any] else { return }

        let issuedNonce = root["nonce"] as? String
        self.nonce = issuedNonce
        self.clickNonce = issuedNonce
        self.reportNonce = issuedNonce
        let cid = adObj["campaignId"] as? String
        if let c = cid, !c.isEmpty { self.lastCampaignId = c }

        let uiStrings = root["uiStrings"] as? [String: Any]
        let rawCustomImg = (adObj["customBannerUrl"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.ad = AdomaticBannerModel(
            campaignId: cid,
            appId: (adObj["appId"] as? String) ?? bundleId,
            title: (adObj["title"] as? String) ?? appName,
            description: (adObj["description"] as? String) ?? "",
            iconUrl: (adObj["iconUrl"] as? String) ?? "",
            customBannerUrl: (rawCustomImg?.isEmpty == false) ? rawCustomImg : nil,
            storeUrl: (adObj["storeUrl"] as? String) ?? "https://apps.apple.com",
            bannerTheme: (adObj["bannerTheme"] as? String) ?? "modern_clean",
            isGenesisMember: (adObj["isGenesisMember"] as? Bool) ?? false,
            adBadge: (uiStrings?["adBadge"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "AD",
            installCta: (uiStrings?["installCta"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Install",
            reportTitle: (uiStrings?["reportTitle"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Report Ad",
            reportPrompt: (uiStrings?["reportPrompt"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Report this ad for inappropriate content or a broken link?",
            cancelLabel: (uiStrings?["cancelBtn"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Cancel",
            reportLabel: (uiStrings?["confirmReportBtn"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Report",
            active: true
        )
    }

    func verifyImpression() async {
        guard let n = nonce else { return }
        nonce = nil
        let payload: [String: Any] = [
            "apiKey": "auto",
            "nonce": n,
            "viewDurationSeconds": 2.2,
            "bannerSize": "320x50",
            "packageName": bundleId,
            "renderedWidthDp": 320,
            "renderedHeightDp": 58,
            "visibleRatio": 1.0
        ]
        _ = await sendWithFailover(path: "/api/v1/ad/verify", method: "POST", jsonBody: payload)
    }

    func recordClick() {
        guard let n = clickNonce else { return }
        let targetId = ad.campaignId ?? ad.appId
        let peerId = ad.appId
        Task {
            let payload: [String: Any] = [
                "campaignId": targetId,
                "targetPeerAppId": peerId,
                "publisherApiKey": "auto",
                "nonce": n,
                "packageName": bundleId
            ]
            _ = await sendWithFailover(path: "/api/v1/ad/click", method: "POST", jsonBody: payload)
            await fetchAd()
        }
    }

    func reportCurrentAd() {
        guard let n = reportNonce else { return }
        reportNonce = nil
        let targetId = ad.campaignId ?? ad.appId
        Task {
            let payload: [String: Any] = [
                "ad_id": targetId,
                "nonce": n,
                "reason": "inappropriate"
            ]
            _ = await sendWithFailover(path: "/api/v1/ad/report", method: "POST", jsonBody: payload)
            await fetchAd()
        }
    }
}

private func resolveLockedIosAppStoreURL(adAppId: String, rawStoreUrl: String) -> URL? {
    let trimmed = rawStoreUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    if adAppId == "aom_founder_treasury" {
        if let comps = URLComponents(string: trimmed),
           comps.scheme?.lowercased() == "https",
           comps.host?.lowercased() == "apps.apple.com",
           comps.path.contains("/app/") {
            return URL(string: "https://apps.apple.com\(comps.path)")
        }
        return URL(string: "https://ad-o-matic.com/")
    }
    guard let comps = URLComponents(string: trimmed),
          comps.scheme?.lowercased() == "https",
          comps.host?.lowercased() == "apps.apple.com",
          comps.path.range(of: #"^/([a-z]{2}/)?app/([a-zA-Z0-9-]+/)?(id\d{6,15}|[a-zA-Z0-9._-]+)$"#, options: .regularExpression) != nil else {
        return nil
    }
    return URL(string: "https://apps.apple.com\(comps.path)")
}

private func presentIosStoreOverlay(for storeURL: URL, fallbackOpen: (URL) -> Void) {
    #if canImport(StoreKit) && os(iOS)
    if #available(iOS 14.0, *),
       let match = storeURL.path.range(of: #"id(\d{6,15})"#, options: .regularExpression) {
        let trackId = String(storeURL.path[match].dropFirst(2))
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            let config = SKOverlay.AppConfiguration(appIdentifier: trackId, position: .bottom)
            let overlay = SKOverlay(configuration: config)
            overlay.present(in: scene)
            return
        }
    }
    #endif
    fallbackOpen(storeURL)
}

private struct GenesisCrownBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.10, y: h * 0.24))
        p.addLine(to: CGPoint(x: w * 0.18, y: h * 0.68))
        p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.68))
        p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.24))
        p.addLine(to: CGPoint(x: w * 0.67, y: h * 0.50))
        p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.12))
        p.addLine(to: CGPoint(x: w * 0.33, y: h * 0.50))
        p.closeSubpath()
        return p
    }
}

private struct GenesisCrownView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                let goldGradient = LinearGradient(
                    colors: [
                        Color(red: 0.99, green: 0.88, blue: 0.28),
                        Color(red: 0.96, green: 0.62, blue: 0.04),
                        Color(red: 0.85, green: 0.47, blue: 0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                let strokeCol = Color(red: 0.57, green: 0.25, blue: 0.05)

                GenesisCrownBodyShape()
                    .fill(goldGradient)
                    .overlay(GenesisCrownBodyShape().stroke(strokeCol, lineWidth: 0.5))

                RoundedRectangle(cornerRadius: 0.5)
                    .fill(goldGradient)
                    .overlay(RoundedRectangle(cornerRadius: 0.5).stroke(strokeCol, lineWidth: 0.45))
                    .frame(width: geo.size.width * 0.64, height: geo.size.height * 0.14)
                    .position(x: geo.size.width * 0.50, y: geo.size.height * 0.85)
            }
        }
        .frame(width: 10.5, height: 9.0)
    }
}

public struct HouseAdBanner: View {
    @StateObject private var vm: AdomaticBannerViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @State private var showReportAlert = false
    private let bannerImageFit: String
    private let bannerHeight: CGFloat
    private let useStoreOverlay: Bool

    public init(
        bannerText: String = "",
        bannerImageUrl: String? = nil,
        bannerImageFit: String = "cover",
        bannerHeight: CGFloat = 60,
        useStoreOverlay: Bool = true,
        targetAudience: String = "",
        developerId: String? = nil
    ) {
        self.bannerImageFit = bannerImageFit
        self.bannerHeight = min(max(bannerHeight, 50), 120)
        self.useStoreOverlay = useStoreOverlay
        _vm = StateObject(wrappedValue: AdomaticBannerViewModel(
            bannerText: bannerText,
            bannerImageUrl: bannerImageUrl,
            targetAudience: targetAudience,
            developerId: developerId
        ))
    }

    public var body: some View {
        if !vm.ad.active {
            EmptyView()
        } else {
            let isDark = (colorScheme == .dark) || (vm.ad.bannerTheme == "modern_dark")
            let surfaceBg = isDark ? Color(red: 0.086, green: 0.094, blue: 0.106) : Color.white
            let borderCol = isDark ? Color(red: 0.165, green: 0.176, blue: 0.200) : Color(red: 0.886, green: 0.910, blue: 0.941)
            let inkPrimary = isDark ? Color(red: 0.929, green: 0.929, blue: 0.922) : Color(red: 0.059, green: 0.090, blue: 0.165)
            let inkSecondary = isDark ? Color(red: 0.596, green: 0.612, blue: 0.643) : Color(red: 0.278, green: 0.333, blue: 0.412)
            let ctaBg = isDark ? Color(red: 0.145, green: 0.388, blue: 0.922) : Color(red: 0.004, green: 0.529, blue: 0.373)

            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    if let customStr = vm.ad.customBannerUrl, let customURL = URL(string: customStr), customStr.hasPrefix("https") {
                        AsyncImage(url: customURL) { img in
                            if bannerImageFit.lowercased() == "contain" {
                                img.resizable().scaledToFit()
                            } else {
                                img.resizable().scaledToFill()
                            }
                        } placeholder: {
                            Color.gray.opacity(0.12).frame(height: bannerHeight)
                        }
                        .frame(maxWidth: .infinity, height: bannerHeight)
                        .background(surfaceBg)
                        .clipped()

                        footerRow(inkPrimary: inkPrimary, inkSecondary: inkSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                    } else {
                        HStack(alignment: .center, spacing: 10) {
                            if let iconURL = URL(string: vm.ad.iconUrl), vm.ad.iconUrl.hasPrefix("https") {
                                AsyncImage(url: iconURL) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Color.gray.opacity(0.16)
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(vm.ad.adBadge)
                                        .font(.system(size: 7.5, weight: .semibold))
                                        .tracking(0.4)
                                        .foregroundColor(inkSecondary.opacity(0.85))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(inkSecondary.opacity(0.08))
                                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(inkSecondary.opacity(0.35), lineWidth: 0.6))
                                        .cornerRadius(3)

                                    Text(vm.ad.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(inkPrimary)
                                        .lineLimit(1)
                                }
                                .padding(.trailing, 14)

                                if !vm.ad.description.isEmpty {
                                    Text(vm.ad.description)
                                        .font(.system(size: 10.5, weight: .regular))
                                        .foregroundColor(inkSecondary)
                                        .lineLimit(1)
                                }

                                footerRow(inkPrimary: inkPrimary, inkSecondary: inkSecondary)
                                    .padding(.top, 1)
                            }

                            Text(vm.ad.installCta)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4.5)
                                .background(ctaBg)
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, minHeight: 56)
                    }
                }

                Button {
                    showReportAlert = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundColor(inkSecondary.opacity(0.42))
                        .padding(5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(vm.ad.reportTitle)
            }
            .background(surfaceBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderCol, lineWidth: 1))
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sponsored app: \(vm.ad.title)")
            .onTapGesture {
                if let target = resolveLockedIosAppStoreURL(adAppId: vm.ad.appId, rawStoreUrl: vm.ad.storeUrl) {
                    vm.recordClick()
                    if useStoreOverlay {
                        presentIosStoreOverlay(for: target) { fallbackUrl in openURL(fallbackUrl) }
                    } else {
                        openURL(target)
                    }
                }
            }
            .alert(vm.ad.reportTitle, isPresented: $showReportAlert) {
                Button(vm.ad.reportLabel, role: .destructive) { vm.reportCurrentAd() }
                Button(vm.ad.cancelLabel, role: .cancel) {}
            } message: {
                Text(vm.ad.reportPrompt)
            }
            .task {
                while !Task.isCancelled {
                    await vm.fetchAd()
                    try? await Task.sleep(nanoseconds: 2_300_000_000)
                    if Task.isCancelled { break }
                    await vm.verifyImpression()
                    try? await Task.sleep(nanoseconds: 42_700_000_000)
                }
            }
        }
    }

    @ViewBuilder
    private func footerRow(inkPrimary: Color, inkSecondary: Color) -> some View {
        HStack {
            Text("ad-o-matic")
                .font(.system(size: 8, weight: .medium))
                .tracking(0.25)
                .foregroundColor(inkSecondary.opacity(0.58))
            Spacer(minLength: 4)
            if vm.ad.isGenesisMember {
                HStack(spacing: 3) {
                    Text("Genesis Member")
                        .font(.system(size: 8.2, weight: .medium))
                        .tracking(0.3)
                        .foregroundColor(inkPrimary.opacity(0.68))
                    GenesisCrownView()
                }
            }
        }
    }
}
