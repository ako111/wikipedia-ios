@preconcurrency import WebKit
import CocoaLumberjackSwift
import WMF
import WMFComponents
import WMFData

class SinglePageWebViewController: ThemeableViewController, WMFNavigationBarConfiguring {
    
    // MARK: - Nested Types
    
    final class DonateConfig {
        let url: URL
        let dataController: WMFDonateDataController
        weak var coordinatorDelegate: DonateCoordinatorDelegate?
        weak var loggingDelegate: WMFDonateLoggingDelegate?
        let completeButtonTitle: String

        internal init(url: URL, dataController: WMFDonateDataController, coordinatorDelegate: DonateCoordinatorDelegate?, loggingDelegate: WMFDonateLoggingDelegate?, completeButtonTitle: String) {
            self.url = url
            self.dataController = dataController
            self.coordinatorDelegate = coordinatorDelegate
            self.loggingDelegate = loggingDelegate
            self.completeButtonTitle = completeButtonTitle
        }
    }
    
    final class YiRLearnMoreConfig {
        let url: URL
        let donateButtonTitle: String
        var donateCoordinator: DonateCoordinator?
        
        internal init(url: URL, donateButtonTitle: String) {
            self.url = url
            self.donateButtonTitle = donateButtonTitle
        }
    }
    
    final class StandardConfig {
        let url: URL
        let useSimpleNavigationBar: Bool
        
        internal init(url: URL, useSimpleNavigationBar: Bool) {
            self.url = url
            self.useSimpleNavigationBar = useSimpleNavigationBar
        }
    }
    
    enum ConfigType {
        case donate(DonateConfig)
        case yirLearnMore(YiRLearnMoreConfig)
        case standard(StandardConfig)
    }
    
    // MARK: - Properties
    
    private let configType: ConfigType
    private var didReachThankYouPage = false
    
    private var loaded = false
    private var didHandleInitialNavigation = false
    
    var useSimpleNavigationBar: Bool {
        switch configType {
        case .donate:
            return true
        case .yirLearnMore:
            return true
        case .standard(let config):
            return config.useSimpleNavigationBar
        }
    }
    
    private var url: URL {
        switch configType {
        case .donate(let config):
            return config.url
        case .yirLearnMore(let config):
            return config.url
        case .standard(let config):
            return config.url
        }
    }
    
    private lazy var webViewConfiguration: WKWebViewConfiguration = {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        // hide mobile frontend header chrome
        let script = """
            let style = document.createElement('style')
            style.innerHTML = '.header-chrome { display: none; }'
            document.head.appendChild(style)
        """
        controller.addUserScript(PageUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController = controller
        config.applicationNameForUserAgent = "WikipediaApp"
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        return config
    }()

    private(set) lazy var webView: WKWebView = {
        let webView = WKWebView(frame: UIScreen.main.bounds, configuration: webViewConfiguration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        return webView
    }()

    private lazy var overlayButtonContainer: UIView = {
        let contentView = UIView(frame: .zero)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = self.theme.colors.paperBackground
        return contentView
    }()
    
    private lazy var overlayButtonSpinner: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = .white
        return activityIndicator
    }()

    private lazy var overlayButton: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        
        let title: String
        switch configType {
        case .donate(let config):
            button.setTitle(config.completeButtonTitle, for: .normal)
            button.titleLabel?.font = WMFFont.for(.headline, compatibleWith: traitCollection)
        case .yirLearnMore(let config):
            button.setTitle(config.donateButtonTitle, for: .normal)
            button.titleLabel?.font = WMFFont.for(.mediumSubheadline, compatibleWith: traitCollection)
        case .standard(let config):
            break
        }
        
        button.backgroundColor = self.theme.colors.link
        button.titleLabel?.textColor = .white
        button.layer.cornerRadius = 8
        
        button.addTarget(self, action: #selector(didTapOverlayButton), for: .touchUpInside)
        return button
    }()
    
    lazy var searchBarButtonItem: UIBarButtonItem = {
        let button = UIBarButtonItem(image: UIImage(named: "search"), style: .plain, target: self, action: #selector(userDidTapSearchButton))
        button.accessibilityLabel = CommonStrings.searchButtonAccessibilityLabel
        return button
    }()
    
    private var dataStore: MWKDataStore {
        return MWKDataStore.shared()
    }
    
    // MARK: - Lifecycle

    required init(configType: ConfigType, theme: Theme) {
        self.configType = configType
        super.init(nibName: nil, bundle: nil)
        self.theme = theme
        
        hidesBottomBarWhenPushed = true
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.wmf_addSubviewWithConstraintsToEdges(webView)

        if useSimpleNavigationBar {
            navigationItem.setRightBarButtonItems([], animated: false)
            navigationItem.titleView = nil
        } else {
            
        }

        copyCookiesFromSession()
    }
    
    
    private func configureNavigationBar() {
        
        var closeConfig: WMFNavigationBarCloseButtonConfig? = nil
        
        if useSimpleNavigationBar {
            let titleConfig = WMFNavigationBarTitleConfig(title: "", customView: nil, alignment: .hidden)
            
            if navigationController?.viewControllers.first === self {
                switch configType {
                case .donate:
                    closeConfig = WMFNavigationBarCloseButtonConfig(text: CommonStrings.cancelActionTitle, target: self, action: #selector(closeButtonTapped(_:)), alignment: .leading)
                default:
                    closeConfig = WMFNavigationBarCloseButtonConfig(text: CommonStrings.doneTitle, target: self, action: #selector(closeButtonTapped(_:)), alignment: .leading)
                }

            }
            configureNavigationBar(titleConfig: titleConfig, closeButtonConfig: closeConfig, profileButtonConfig: nil, tabsButtonConfig: nil, searchBarConfig: nil, hideNavigationBarOnScroll: false)

        } else {
            let wButton = UIButton(type: .custom)
            wButton.setImage(UIImage(named: "W"), for: .normal)
            wButton.addTarget(self, action: #selector(wButtonTapped(_:)), for: .touchUpInside)
            
            let titleConfig = WMFNavigationBarTitleConfig(title: "", customView: wButton, alignment: .hidden)
            
            configureNavigationBar(titleConfig: titleConfig, closeButtonConfig: closeConfig, profileButtonConfig: nil, tabsButtonConfig: nil, searchBarConfig: nil, hideNavigationBarOnScroll: true)
            
            let safariItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(tappedAction(_:)))
            navigationItem.setRightBarButtonItems([searchBarButtonItem, safariItem], animated: false)
            
            if let rightBarButtonItems = navigationItem.rightBarButtonItems {
                for item in rightBarButtonItems {
                    item.tintColor = theme.colors.link
                }
            }
        }
    }
    
    @objc private func wButtonTapped(_ sender: UIButton) {
        navigationController?.popToRootViewController(animated: true)
    }

    private func fetch() {
        webView.load(URLRequest(url: url))
    }
    
    var fetched = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        guard !loaded else {
            return
        }
        loaded = true
        load()
        
        configureNavigationBar()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        switch configType {
        case .donate(let config):
            if config.url.isDonationURL {
                config.loggingDelegate?.handleDonateLoggingAction(.webViewFormDidAppear)
            }
        case .yirLearnMore:
            setupButtonOverlay()
        case .standard:
            break
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        switch configType {
        case .donate(let config):
            if didReachThankYouPage {
                config.loggingDelegate?.handleDonateLoggingAction(.webViewFormThankYouDidDisappear)
                config.coordinatorDelegate?.handleDonateAction(.webViewFormThankYouDidDisappear)
            }
        case .yirLearnMore:
            break
        case .standard:
            break
        }
    }
    
    public override var preferredContentSize: CGSize {
        get {
            return CGSize(width: 1400, height: 1400)
        } set {
            super.preferredContentSize = newValue
        }
    }
    
    // MARK: - Actions
    
    @objc func userDidTapSearchButton() {
        let searchVC = SearchViewController(source: .unknown)
        searchVC.shouldBecomeFirstResponder = true
        searchVC.apply(theme: theme)
        searchVC.dataStore = dataStore
        searchVC.needsCenteredTitle = true
        
        navigationController?.pushViewController(searchVC, animated: true)
    }
    
    @objc private func tappedAction(_ sender: UIBarButtonItem) {
        let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: [TUSafariActivity()])
        
        if let popover = activityViewController.popoverPresentationController {
            popover.barButtonItem = sender
            popover.permittedArrowDirections = .any
        }

        activityViewController.excludedActivityTypes = [.addToReadingList]
        present(activityViewController, animated: true)
    }
    
    @objc private func closeButtonTapped(_ sender: UIButton) {
        
        switch configType {
        case .donate:
            break
        case .yirLearnMore(let config):
            config.donateCoordinator = nil
        case .standard:
            break
        }
        
        navigationController?.dismiss(animated: true)
    }

    @objc private func didTapOverlayButton() {
        switch configType {
        case .donate(let config):
            config.loggingDelegate?.handleDonateLoggingAction(.webViewFormThankYouDidTapReturn)
            config.coordinatorDelegate?.handleDonateAction(.webViewFormThankYouDidTapReturn)
        case .yirLearnMore(let config):
            
            guard let navigationController else {
                return
            }
            
            if let metricsID = DonateCoordinator.metricsID(for: .yearInReview, languageCode: dataStore.languageLinkController.appLanguage?.languageCode) {
                DonateFunnel.shared.logYearInReviewDonateSlideLearnMoreWebViewDidTapDonateButton(metricsID: metricsID)
            }
            
            let coordinator = DonateCoordinator(
                navigationController: navigationController,
                donateButtonGlobalRect: overlayButtonContainer.frame,
                source: .yearInReview,
                dataStore: dataStore,
                theme: theme,
                navigationStyle: .push,
                setLoadingBlock: { [weak self] isLoading in
                    self?.setOverlayButtonLoading(isLoading)
            })
            coordinator.start()
            config.donateCoordinator = coordinator
        case .standard:
            break
        }
    }
    
    // MARK: - Private
    
    private func copyCookiesFromSession() {
        let cookies = Session.sharedCookieStorage.cookies ?? []
        for cookie in cookies {
            webView.configuration.websiteDataStore.httpCookieStore
                .setCookie(cookie)
        }
    }

    private func load() {
        webView.load(URLRequest(url: url))
    }

    private func setupButtonOverlay() {
        webView.addSubview(overlayButtonContainer)
        overlayButtonContainer.addSubview(overlayButton)
        overlayButton.addSubview(overlayButtonSpinner)

        let bottom = overlayButtonContainer.bottomAnchor.constraint(equalTo: webView.bottomAnchor)
        let leading = overlayButtonContainer.leadingAnchor.constraint(equalTo: webView.leadingAnchor)
        let trailing = overlayButtonContainer.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
        let height = overlayButtonContainer.heightAnchor.constraint(equalToConstant: 90)

        let buttonTop = overlayButton.topAnchor.constraint(equalTo: overlayButtonContainer.topAnchor, constant: 12)
        let buttonLeading = overlayButton.leadingAnchor.constraint(equalTo: overlayButtonContainer.leadingAnchor, constant: 12)
        let buttonTrailing = overlayButton.trailingAnchor.constraint(equalTo: overlayButtonContainer.trailingAnchor, constant: -12)
        let buttonBottom = overlayButton.bottomAnchor.constraint(equalTo: overlayButtonContainer.bottomAnchor, constant: -32)
        
        let spinnerCenterX = overlayButtonSpinner.centerXAnchor.constraint(equalTo: overlayButton.centerXAnchor)
        let spinnerCenterY = overlayButtonSpinner.centerYAnchor.constraint(equalTo: overlayButton.centerYAnchor)

        webView.addConstraints([bottom, leading, trailing, height, buttonTop, buttonLeading, buttonTrailing, buttonBottom, spinnerCenterX, spinnerCenterY])
    }

    private func handleNavigation(with action: WKNavigationAction) -> Bool {
        guard didHandleInitialNavigation else {
            didHandleInitialNavigation = true
            return true
        }
        
        guard
            let relativeActionURL = action.request.url,
            let actionURL = URL(string: relativeActionURL.absoluteString, relativeTo: webView.url)?.absoluteURL else {
            return true
        }
        
        // Fake a donation if developer settings toggle is on
        if WMFDeveloperSettingsDataController.shared.bypassDonation,
           let host = actionURL.host(),
           host == "payments.wikimedia.org",
           let thankYouURL = URL(string: "https://thankyou.wikipedia.org/wiki/Thank_You/en?country=US") {
            
            // Skip to thank you page
            webView.load(URLRequest(url: thankYouURL))
            
            // Save fake donation
            saveDonationToLocalHistory(donationInfo: DonationInfo(amount: "1", country: "US", currency: "USD", isRecurring: false), dataController: WMFDonateDataController.shared)
            return false
        }
        
        if action.navigationType == .linkActivated {
            
            let legacyNavigateAction = { [weak self] in
                let userInfo: [AnyHashable : Any] = [RoutingUserInfoKeys.source: RoutingUserInfoSourceValue.inAppWebView.rawValue]
                self?.navigate(to: actionURL, userInfo: userInfo)
            }
            
            // first try to navigate using LinkCoordinator. If it fails, use the legacy approach.
            if let navigationController {
                let linkCoordinator = LinkCoordinator(navigationController: navigationController, url: actionURL, dataStore: dataStore, theme: theme, articleSource: .undefined)
                let success = linkCoordinator.start()
                guard success else {
                    legacyNavigateAction()
                    return false
                }
                
                return false
            }
            
            legacyNavigateAction()
            return false
        } else if action.navigationType == .other {
            
            switch configType {
            case .donate(let config):
                if actionURL.isThankYouDonationURL {
                    didReachThankYouPage = true
                    let parsedDonationInfo = parseThankYouURL(actionURL)
                    saveDonationToLocalHistory(donationInfo: parsedDonationInfo, dataController: config.dataController)
                    setupButtonOverlay()
                    config.loggingDelegate?.handleDonateLoggingAction(.webViewFormThankYouPageDidAppear)
                }
            case .yirLearnMore:
                break
            case .standard:
                break
            }
        }
        
        return true
    }
    
    // MARK: - Donate Config Logic

    func parseThankYouURL(_ url: URL) -> DonationInfo? {
        guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let queryItems = urlComponents.queryItems ?? []
        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            (item.name, item.value)
        })

        guard let amount = queryDict["amount"],
              let country = queryDict["country"],
              let currency = queryDict["currency"] else {
            return nil
        }

        let isRecurring = queryDict["recurring"] == "true" || queryDict.keys.contains("recurring") && queryDict["recurring"] == nil

        let donationInfo = DonationInfo(amount: amount, country: country, currency: currency, isRecurring: isRecurring)

        return donationInfo
    }

    private func saveDonationToLocalHistory(donationInfo: DonationInfo?, dataController: WMFDonateDataController) {
        guard let donationInfo,
        let decimalAmount = Decimal(string: donationInfo.amount ?? String()),
                let currency = donationInfo.currency else {
            return
        }

        let donationType: WMFDonateLocalHistory.DonationType = donationInfo.isRecurring ? .recurring : .oneTime

        dataController.saveLocalDonationHistory(type: donationType, amount: decimalAmount, currencyCode: currency, isNative: false)
    }
    
    // MARK: - YiR Learn More Config Logic
        
    private func setOverlayButtonLoading(_ isLoading: Bool) {
        switch configType {
        case .donate:
            DDLogError("Unexpected config for setOverlayButtonLoading")
        case .yirLearnMore:
            
            if isLoading {
                overlayButton.titleLabel?.alpha = 0
                overlayButtonSpinner.startAnimating()
            } else {
                overlayButton.titleLabel?.alpha = 1
                overlayButtonSpinner.stopAnimating()
            }
            
            
        case .standard:
            DDLogError("Unexpected config for setOverlayButtonLoading")
        }
    }
    
    override func apply(theme: Theme) {
        super.apply(theme: theme)
        
        themeNavigationBarCustomCenteredTitleView()
        
        if let rightBarButtonItems = navigationItem.rightBarButtonItems {
            for item in rightBarButtonItems {
                item.tintColor = theme.colors.link
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension SinglePageWebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard handleNavigation(with: navigationAction) else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        guard handleNavigation(with: navigationAction) else {
            decisionHandler(.cancel, preferences)
            return
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        DDLogWarn("Error loading single page - did fail provisional navigation: \(error)")
        WMFAlertManager.sharedInstance.showErrorAlert(error as NSError, sticky: false, dismissPreviousAlerts: true)
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        DDLogWarn("Error loading single page: \(error)")

        // Avoid displaying "Plug-in handled load" noise to users.
        if (error as NSError).isPluginHandledLoadError {
            return
        }

        WMFAlertManager.sharedInstance.showErrorAlert(error as NSError, sticky: false, dismissPreviousAlerts: false)
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {

    }
}

// MARK: - WKUIDelegate

extension SinglePageWebViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        let action1 = UIAlertAction(title: CommonStrings.okTitle, style: .default) { _ in
            completionHandler(true)
        }
        let action2 = UIAlertAction(title: CommonStrings.cancelActionTitle, style: .default) { _ in
            completionHandler(false)
        }
        alertController.addAction(action1)
        alertController.addAction(action2)
        
        present(alertController, animated: true)
    }
}

private extension NSError {
  var isPluginHandledLoadError: Bool {
      domain == "WebKitErrorDomain" && code == 204
  }
}

struct DonationInfo {
    let amount: String?
    let country: String?
    let currency: String?
    let isRecurring: Bool
}
