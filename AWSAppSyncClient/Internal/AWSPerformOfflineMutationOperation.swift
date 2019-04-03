//
// Copyright 2019 Amazon.com, Inc. or its affiliates. All Rights Reserved.
// Licensed under the Amazon Software License
// http://aws.amazon.com/asl/
//

import Foundation

final class AWSPerformOfflineMutationOperation: AsynchronousOperation, Cancellable {
    private weak var appSyncClient: AWSAppSyncClient?
    private weak var networkClient: AWSNetworkTransport?
    private let handlerQueue: DispatchQueue
    let mutation: AWSAppSyncMutationRecord

    var operationCompletionBlock: ((AWSPerformOfflineMutationOperation, Error?) -> Void)?

    init(
        appSyncClient: AWSAppSyncClient?,
        networkClient: AWSNetworkTransport?,
        handlerQueue: DispatchQueue,
        mutation: AWSAppSyncMutationRecord) {
        self.appSyncClient = appSyncClient
        self.networkClient = networkClient
        self.handlerQueue = handlerQueue
        self.mutation = mutation
    }

    deinit {
        AppSyncLog.verbose("\(mutation.recordIdentifier): deinit")
    }

    private func send(_ mutation: AWSAppSyncMutationRecord,
                      completion: @escaping ((JSONObject?, Error?) -> Void)) {
        guard
            let data = mutation.data,
            let networkClient = networkClient
            else {
                completion(nil, nil)
                return
        }

        networkClient.send(data: data) { result, error in
            completion(result, error)
        }
    }

    private func send(completion: @escaping ((JSONObject?, Error?) -> Void)) {
        guard let appSyncClient = appSyncClient else {
            return
        }

        if let s3Object = mutation.s3ObjectInput {
            appSyncClient.s3ObjectManager?.upload(s3Object: s3Object) { [weak self, mutation] success, error in
                if success {
                    self?.send(mutation, completion: completion)
                } else {
                    completion(nil, error)
                }
            }
        } else {
            send(mutation, completion: completion)
        }
    }

    private func notifyCompletion(_ result: JSONObject?, error: Error?) {
        operationCompletionBlock?(self, error)

        handlerQueue.async { [weak self] in
            guard
                let self = self,
                let appSyncClient = self.appSyncClient,
                let offlineMutationDelegate = appSyncClient.offlineMutationDelegate
                else {
                    return
            }

            // call master delegate
            offlineMutationDelegate.mutationCallback(
                recordIdentifier: self.mutation.recordIdentifier,
                operationString: self.mutation.operationString!,
                snapshot: result,
                error: error)
        }
    }

    // MARK: Operation

    override func start() {
        if isCancelled {
            state = .finished
            return
        }

        state = .executing

        send { result, error in
            if AWSPerformOfflineMutationOperation.shouldRetry(self.getErrorType(result), error) {
                // delay 1 second and retry
                sleep(1)
                self.start()
                return
            }
            
            if error == nil {
                self.notifyCompletion(result, error: nil)
                self.state = .finished
                return
            }

            if self.isCancelled {
                self.state = .finished
                return
            }

            self.notifyCompletion(result, error: error)
            self.state = .finished
        }
    }
    
    fileprivate func getErrorType(_ result: JSONObject?) -> String? {
        if let errors = result?["errors"] as? [Any],
            let aError = errors.first as? [String:Any],
            let errorType = aError["errorType"] as? String  {
            return errorType
        }
        return nil
    }
    
    // MARK: CustomStringConvertible

    override var description: String {
        var desc: String = "<\(self):\(mutation.self)"
        desc.append("\tmutation: \(mutation)")
        desc.append("\tstate: \(state)")
        desc.append(">")

        return desc
    }
}

extension AWSPerformOfflineMutationOperation{
    class func shouldRetry(_ errorType: String?, _ error: Error?) -> Bool {
        if let aError = error as? AWSAppSyncClientError {
            // debug log
            // printAWSAppSyncClientError(aError)
            return true
        }

        if let errorType = errorType {
            if errorType == "DynamoDB:ProvisionedThroughputExceededException" {
                AppSyncLog.debug("Retry MutationOperation: DynamoDB:ProvisionedThroughputExceededException")
                return true
            } else {
                // DynamoDB:ConditionalCheckFailedException
                // unique ID

                // DynamoDB:AmazonDynamoDBException
                // item size > 400KB
                // parameter value > 1KB
                return false
            }
        }
        return false
    }
    
    class func printAWSAppSyncClientError(_ aAWSAppSyncClientError: AWSAppSyncClientError) {
        // debug log
        switch aAWSAppSyncClientError {
        case .requestFailed(_, let aHTTPURLResponse, let aError):
            AppSyncLog.debug("Retry MutationOperation: requestFailed HTTPURLResponse \(String(describing: aHTTPURLResponse))")
            AppSyncLog.debug("Retry MutationOperation: requestFailed Error \(String(describing: aError))")
            AppSyncLog.debug("Retry MutationOperation: requestFailed Unauthorized \(aHTTPURLResponse?.statusCode == 401)")
            if let aNSError = aError as NSError? {
                AppSyncLog.debug("Retry MutationOperation: requestFailed NSError.code \(aNSError.code)")
                AppSyncLog.debug("Retry MutationOperation: requestFailed NSURLErrorTimedOut \(aNSError.code == NSURLErrorTimedOut)")
                AppSyncLog.debug("Retry MutationOperation: requestFailed NSURLErrorNotConnectedToInternet \(aNSError.code == NSURLErrorNotConnectedToInternet)")
            }
            break
        default:
            break
        }
    }
}
