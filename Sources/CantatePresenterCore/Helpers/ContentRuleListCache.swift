import Foundation
import WebKit
import os

// MARK: - Content Rule List Cache

/// Lista reguł WebKit kompilowana raz na uruchomienie i podawana kolejnym widokom (plansza: blokada sieci,
/// Śpiewnik Wywroty: reklamy). Wywołujący czekają na wynik kompilacji; przy błędzie dostają `nil`.
@MainActor
final class ContentRuleListCache {
    let identifier: String
    let encodedRules: String
    private let logger: Logger
    private var ruleList: WKContentRuleList?
    private var failed = false
    private var waiting: [(WKContentRuleList?) -> Void] = []

    init(identifier: String, encodedRules: String, logCategory: String) {
        self.identifier = identifier
        self.encodedRules = encodedRules
        self.logger = Logger(subsystem: "com.cantate.presenter", category: logCategory)
    }

    /// Wywołuje `completion` z listą reguł (od razu, jeśli jest już skompilowana) albo z `nil`, gdy kompilacja się
    /// nie udała.
    func withRuleList(_ completion: @escaping (WKContentRuleList?) -> Void) {
        if let ruleList { return completion(ruleList) }
        if failed { return completion(nil) }
        waiting.append(completion)
        guard waiting.count == 1 else { return }
        compile(in: WKContentRuleListStore.default()) { [self] list in
            ruleList = list
            failed = list == nil
            let callbacks = waiting
            waiting = []
            callbacks.forEach { $0(list) }
        }
    }

    /// Kompiluje listę w podanym magazynie; `nil` przy błędzie (zapisanym w dzienniku).
    func compile(in store: WKContentRuleListStore?, completion: @escaping @MainActor (WKContentRuleList?) -> Void) {
        guard let store else {
            logger.error("Brak magazynu reguł WebKit (\(self.identifier, privacy: .public))")
            return completion(nil)
        }
        let logger = logger
        let identifier = identifier
        store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: encodedRules) { list, error in
            if let error {
                logger.error("Nie udało się skompilować reguł \(identifier, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            MainActor.assumeIsolated { completion(list) }
        }
    }
}
