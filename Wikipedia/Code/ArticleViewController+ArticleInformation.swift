import WMFComponents

extension ArticleViewController {
    func showLanguages() {
        let languagesVC = WMFArticleLanguagesViewController(articleURL: articleURL)
        themesPresenter.dismissReadingThemesPopoverIfActive(from: self)
        languagesVC.delegate = self
        languagesVC.apply(theme)
        presentEmbedded(languagesVC)
    }
    
    func showDisambiguation(with payload: Any?) {
        guard let payload = payload as? [[String: Any]] else {
            showGenericError()
            return
        }
        var pageURLs: [URL] = []
        for info in payload {
            guard let links = info["links"] as? [String] else {
                continue
            }
            let linkURLs = links.compactMap { URL(string: $0) }
            pageURLs.append(contentsOf: linkURLs)
        }
        let listVC = DisambiguationPagesViewController(with: pageURLs, siteURL: articleURL, dataStore: dataStore, theme: theme)
        push(listVC)
    }
    
    func showEditHistory() {
        
        guard let title = articleURL.wmf_title else {
            showGenericError()
            return
        }
        
        EditHistoryCompareFunnel.shared.logShowHistory(articleURL: articleURL)
        
        let historyVC = PageHistoryViewController(pageTitle: title, pageURL: articleURL, articleSummaryController: dataStore.articleSummaryController, authenticationManager: dataStore.authenticationManager)
        historyVC.apply(theme: theme)
        push(historyVC)
    }
    
    func showTalkPage() {
        guard let talkPageURL = articleURL.articleTalkPage else {
            showGenericError()
            return
        }
        
        let userInfo: [AnyHashable : Any] = [RoutingUserInfoKeys.source: RoutingUserInfoSourceValue.article.rawValue]
        navigate(to: talkPageURL, userInfo: userInfo)
    }
    
    func showCoordinate() {
        let placesURL = NSUserActivity.wmf_URLForActivity(of: .places, withArticleURL: articleURL)
        UIApplication.shared.open(placesURL)
    }
    
    func showPageIssues(with payload: Any?) {
        guard let payload = payload as? [[String: Any]] else {
            showGenericError()
            return
        }
        let issues = payload.compactMap { ($0["html"] as? String)?.removingHTML }
        let issuesVC = PageIssuesTableViewController(style: .grouped)
        issuesVC.issues = issues
        presentEmbedded(issuesVC)
    }
}

extension ArticleViewController: WMFLanguagesViewControllerDelegate {
    func languagesController(_ controller: WMFLanguagesViewController, didSelectLanguage language: MWKLanguageLink) {
        dismiss(animated: true) { [weak self] in
            
            guard let self else { return }
            
            guard let navVC = self.navigationController else { return }
            let articleCoordinator = ArticleCoordinator(navigationController: navVC, articleURL: language.articleURL, dataStore: dataStore, theme: theme, source: .undefined, previousPageViewObjectID: pageViewObjectID)
            articleCoordinator.start()
            
            NavigationEventsFunnel.shared.logEvent(action: .articleToolbarLangSuccess)
        }
    }
}
