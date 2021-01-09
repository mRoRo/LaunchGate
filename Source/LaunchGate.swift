import Foundation

public enum LaunchgateState {
    case requiredUpdate
    case blockingUpdateAlert
    case optionalUpdate
    case noUpdate
    case fileError(_ error: String)
}

extension LaunchgateState: Equatable {
    static public func == (lhs: LaunchgateState, rhs: LaunchgateState) -> Bool {
        switch (lhs, rhs) {
        case (.requiredUpdate, .requiredUpdate): return true
        case (.blockingUpdateAlert, .blockingUpdateAlert): return true
        case (.optionalUpdate, .optionalUpdate): return true
        case (.noUpdate, .noUpdate): return true
        case (.fileError(let error1), .fileError(let error2)):
            return (error1 == error2) ? true : false
        default:
            return false
        }
    }
}

public protocol LaunchGateDelegate: class {
    func updateLaunchgateState(_ state: LaunchgateState)
}

/// Custom internal error type
typealias LaunchGateError = Error & CustomStringConvertible

public class LaunchGate: LaunchGateFileDelegate {

    /// Parser to use when parsing the configuration file
    public var parser: LaunchGateParser!

    /// URI for the configuration file
    var configurationFileURL: URL!

    /// App Store URI ("itms-apps://itunes.apple.com/...") for the current app
    var updateURL: URL!

    /// Manager object for the various alert dialogs
    var dialogManager: DialogManager!
    public weak var delegate: LaunchGateDelegate?

    // MARK: - Public API

    /**
     Failable initializer. If either the `configURI` or `appStoreURI` are unable to be
     converted into an `URL` (i.e. containing illegal URL characters) this initializer
     will return `nil`.
     
     - Parameters:
        - configURI: URI for the configuration file
        - appStoreURI: App Store URI ("itms-apps://itunes.apple.com/...") for the current app
     
     - Returns: A `LaunchGate` instance or `nil`
     */
    public init?(configURI: String, appStoreURI: String) {
        guard let configURL = URL(string: configURI) else { return nil }
        guard let appStoreURL = URL(string: appStoreURI) else { return nil }

        configurationFileURL = configURL
        updateURL = appStoreURL
        parser = DefaultParser()
        dialogManager = DialogManager()
    }

    /// Check the configuration file and perform any appropriate action.
    public func check() {
        performCheck(RemoteFileManager(remoteFileURL: (configurationFileURL as URL)))
    }

    // MARK: - Internal API

    /**
     Check the configuration file and perform any appropriate action, using
     the provided `RemoteFileManager`.
     
     - Parameter remoteFileManager: The `RemoteFileManager` to use to fetch the configuration file.
     */
    func performCheck(_ remoteFileManager: RemoteFileManager) {
        remoteFileManager.delegate = self
        weak var weakSelf = self
        remoteFileManager.fetchRemoteFile { (jsonData) -> Void in
            guard let config = self.parser.parse(jsonData) else {
                weakSelf?.delegate?.updateLaunchgateState(.fileError(LaunchGateFileError.error.rawValue))
                return }

            self.displayDialogIfNecessary(config, dialogManager: self.dialogManager)
        }
    }

    /**
     Determine which dialog, if any, to display based on the parsed configuration.
     
     - Parameters:
        - config:        Configuration parsed from remote configuration file.
        - dialogManager: Manager object for the various alert dialogs
     */
    func displayDialogIfNecessary(_ config: LaunchGateConfiguration, dialogManager: DialogManager) {
        weak var weakSelf = self
        if let reqUpdate = config.requiredUpdate,
           let appVersion = currentAppVersion(),
           shouldShowRequiredUpdateDialog(reqUpdate, appVersion: appVersion) {
            weakSelf?.delegate?.updateLaunchgateState(.requiredUpdate)
            dialogManager.displayRequiredUpdateDialog(reqUpdate, updateURL: updateURL)
        } else if let alert = config.alert,
                  shouldShowAlertDialog(alert) {
            weakSelf?.delegate?.updateLaunchgateState(.blockingUpdateAlert)
            dialogManager.displayAlertDialog(alert, blocking: alert.blocking)
        } else if let optUpdate = config.optionalUpdate,
                  let appVersion = currentAppVersion(),
                  shouldShowOptionalUpdateDialog(optUpdate, appVersion: appVersion) {
            weakSelf?.delegate?.updateLaunchgateState(.optionalUpdate)
            dialogManager.displayOptionalUpdateDialog(optUpdate, updateURL: updateURL)
        } else {
            weakSelf?.delegate?.updateLaunchgateState(.noUpdate)
        }
    }

    /**
     Determine if an alert dialog should be displayed, based on the configuration.
     
     - Parameter alertConfig: An `AlertConfiguration`, parsed from the configuration file.
     
     - Returns: `true`, if an alert dialog should be displayed; `false`, if not.
     */
    func shouldShowAlertDialog(_ alertConfig: AlertConfiguration) -> Bool {
        alertConfig.blocking || alertConfig.isNotRemembered()
    }

    /**
     Determine if an optional update dialog should be displayed, based on the configuration.
     
     - Parameter updateConfig: An `UpdateConfiguration`, parsed from the configuration file.
     
     - Returns: `true`, if an optional update should be displayed; `false`, if not.
     */
    func shouldShowOptionalUpdateDialog(_ updateConfig: UpdateConfiguration, appVersion: String) -> Bool {
        guard updateConfig.isNotRemembered() else { return false }

        return appVersion < updateConfig.version
    }

    /**
     Determine if a required update dialog should be displayed, based on the configuration.
     
     - Parameter updateConfig: An `UpdateConfiguration`, parsed from the configuration file.
     
     - Returns: `true`, if a required update dialog should be displayed; `false`, if not.
     */
    func shouldShowRequiredUpdateDialog(_ updateConfig: UpdateConfiguration, appVersion: String) -> Bool {
        appVersion < updateConfig.version
    }

    func currentAppVersion() -> String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
    // LaunchGateFileDelegate
    func fileError(_ error: LaunchGateFileError) {
        weak var weakSelf = self
        weakSelf?.delegate?.updateLaunchgateState(.fileError(error.rawValue))
    }
}
