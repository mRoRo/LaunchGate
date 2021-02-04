import Foundation

enum LaunchGateFileError: String {
    case errorEmptyResponse
    case errorNoData
    case error
}

protocol LaunchGateFileDelegate: AnyObject {
    func fileError(_ error: LaunchGateFileError)
}

class RemoteFileManager {

    let remoteFileURL: URL
    weak var delegate: LaunchGateFileDelegate?

    init(remoteFileURL: URL) {
        self.remoteFileURL = remoteFileURL
    }

    func fetchRemoteFile(_ callback: @escaping (Data) -> Void) {
        performRemoteFileRequest(URLSession.shared, url: remoteFileURL, responseHandler: callback)
    }

    func performRemoteFileRequest(_ session: URLSession, url: URL, responseHandler: @escaping (_ data: Data) -> Void) {
        weak var weakSelf = self
        let task = session.dataTask(with: url) { data, response, error in
            if let error = error {
                print("LaunchGate — Error: \(error.localizedDescription)")
                weakSelf?.delegate?.fileError(.error)
            }

            guard response != nil else {
                print("LaunchGate - Error because there is no response")
                weakSelf?.delegate?.fileError(.errorEmptyResponse)
                return
            }

            guard let data = data else {
                print("LaunchGate — Error: Remote configuration file response was empty.")
                weakSelf?.delegate?.fileError(.errorNoData)
                return
            }

            responseHandler(data)
        }

        task.resume()
    }

}
