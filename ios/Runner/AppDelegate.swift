import UIKit
import Flutter
import AVFoundation
import WebKit

/// Hidden WKWebView runner that solves mirror anti-bot interstitials.
///
/// Many 91 mirror domains serve a "Redirecting…" page whose inline JS checks
/// adblock presence, navigator.webdriver, GPU, timezone and then does
/// `document.write('<a href=...>'); .click()` to bounce to the real page and
/// set a cookie. A plain HTTP client just receives that tiny JS page.
/// WKWebView executes it naturally, follows the redirect, and we then read the
/// final DOM (which contains the real page incl. the `strencode2(...)` payload)
/// plus the cookies it set.
final class ChallengeWebViewRunner: NSObject, WKNavigationDelegate {
  private var webView: WKWebView?
  private var completion: ((Result<[String: Any], Error>) -> Void)?
  private var settleWork: DispatchWorkItem?
  private var timeoutWork: DispatchWorkItem?
  private var retries = 0
  private var done = false

  func solve(
    url: URL,
    headers: [String: String],
    timeoutMs: Double,
    completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    self.completion = completion
    let timeout = max(6.0, timeoutMs / 1000.0)

    let config = WKWebViewConfiguration()
    config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
    let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 4, height: 4), configuration: config)
    if let ua = headers["User-Agent"] {
      wv.customUserAgent = ua
    }
    wv.navigationDelegate = self
    wv.alpha = 0.02
    wv.isOpaque = false
    wv.isUserInteractionEnabled = false
    if let win = Self.keyWindow() {
      // Must be in the window hierarchy for JS timers/rendering to run; keep it
      // tiny and nearly transparent, and non-interactive so it never steals taps.
      win.addSubview(wv)
    }
    webView = wv

    var req = URLRequest(url: url)
    req.timeoutInterval = timeout
    for (k, v) in headers where k.lowercased() != "user-agent" {
      req.setValue(v, forHTTPHeaderField: k)
    }
    wv.load(req)

    let tw = DispatchWorkItem { [weak self] in
      self?.finish(.failure(NSError(
        domain: "p91.challenge",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "WKWebView challenge timeout"]
      )))
    }
    timeoutWork = tw
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: tw)
  }

  // MARK: - WKNavigationDelegate

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    scheduleSettle()
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    finish(.failure(error))
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    finish(.failure(error))
  }

  // MARK: - Internals

  private func scheduleSettle() {
    settleWork?.cancel()
    let w = DispatchWorkItem { [weak self] in self?.extract() }
    settleWork = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: w)
  }

  private func extract() {
    guard let wv = webView, !done else { return }
    wv.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
      guard let self = self, !self.done else { return }
      if let error = error {
        self.finish(.failure(error))
        return
      }
      let html = (result as? String) ?? ""
      let lower = html.lowercased()
      let stillChallenge =
        (lower.contains("redirecting") && lower.contains("loading")) ||
        lower.contains("just a moment") ||
        lower.contains("cf-chl") ||
        lower.contains("verify you are human")
      if stillChallenge && self.retries < 6 {
        self.retries += 1
        self.scheduleSettle()
        return
      }
      wv.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
        var map: [String: String] = [:]
        for c in cookies { map[c.name] = c.value }
        self.finish(.success([
          "html": html,
          "cookies": map,
          "finalUrl": wv.url?.absoluteString ?? ""
        ]))
      }
    }
  }

  private func finish(_ result: Result<[String: Any], Error>) {
    if done { return }
    done = true
    settleWork?.cancel()
    timeoutWork?.cancel()
    webView?.stopLoading()
    webView?.removeFromSuperview()
    webView = nil
    completion?(result)
    completion = nil
  }

  private static func keyWindow() -> UIWindow? {
    if #available(iOS 13.0, *) {
      for scene in UIApplication.shared.connectedScenes {
        if let ws = scene as? UIWindowScene {
          if let w = ws.windows.first(where: { $0.isKeyWindow }) { return w }
          if let w = ws.windows.first { return w }
        }
      }
    }
    return UIApplication.shared.windows.first
  }
}

/// Hosts two method channels:
///  - `p91/device`    : setBrightness / resetBrightness / share
///  - `p91/challenge` : solveChallenge -> hidden WKWebView anti-bot runner
///
/// Keeping these tiny native helpers in-tree avoids third-party CocoaPods and
/// makes the unsigned GitHub Actions IPA build deterministic.
@main
@objc class AppDelegate: FlutterAppDelegate {

  private var initialBrightness: CGFloat = 1.0
  private var challengeRunner: ChallengeWebViewRunner?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Background / lock-screen playback.
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      NSLog("AVAudioSession error: \(error)")
    }

    initialBrightness = UIScreen.main.brightness

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    registerDeviceChannel(controller)
    registerChallengeChannel(controller)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - p91/device

  private func registerDeviceChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(name: "p91/device", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterMethodNotImplemented); return }
      switch call.method {
      case "setBrightness":
        if let args = call.arguments as? [String: Any], let value = args["value"] as? Double {
          DispatchQueue.main.async {
            UIScreen.main.brightness = CGFloat(min(max(value, 0.0), 1.0))
          }
          result(nil)
        } else {
          result(FlutterError(code: "BAD_ARGS", message: "value required", details: nil))
        }

      case "resetBrightness":
        DispatchQueue.main.async { UIScreen.main.brightness = self.initialBrightness }
        result(nil)

      case "share":
        let text = (call.arguments as? [String: Any])?["text"] as? String ?? ""
        DispatchQueue.main.async {
          let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
          if let pop = vc.popoverPresentationController {
            pop.sourceView = controller.view
            pop.sourceRect = CGRect(
              x: controller.view.bounds.midX,
              y: controller.view.bounds.midY,
              width: 0, height: 0
            )
            pop.permittedArrowDirections = []
          }
          controller.present(vc, animated: true, completion: nil)
        }
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - p91/challenge

  private func registerChallengeChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(name: "p91/challenge", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterMethodNotImplemented); return }
      guard call.method == "solveChallenge" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      guard let urlStr = args["url"] as? String, let url = URL(string: urlStr) else {
        result(FlutterError(code: "BAD_ARGS", message: "url required", details: nil))
        return
      }
      var headers: [String: String] = [:]
      if let raw = args["headers"] as? [String: Any] {
        for (k, v) in raw {
          if let ks = k as? String, let vs = v as? String { headers[ks] = vs }
        }
      }
      var timeout: Double = 25000
      if let d = args["timeoutMs"] as? Double { timeout = d }
      else if let i = args["timeoutMs"] as? Int { timeout = Double(i) }

      let runner = ChallengeWebViewRunner()
      self.challengeRunner = runner
      runner.solve(url: url, headers: headers, timeoutMs: timeout) { [weak self] res in
        DispatchQueue.main.async {
          self?.challengeRunner = nil
          switch res {
          case .success(let payload):
            result(payload)
          case .failure(let error):
            result(FlutterError(code: "CHALLENGE_FAILED", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }
}
