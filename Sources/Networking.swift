import Foundation

public extension Int {
    /**
     Categorizes a status code.
     - returns: The NetworkingStatusCodeType of the status code.
     */
    public func statusCodeType() -> Networking.StatusCodeType {
        if self >= 100 && self < 200 {
            return .informational
        } else if self >= 200 && self < 300 {
            return .successful
        } else if self >= 300 && self < 400 {
            return .redirection
        } else if self >= 400 && self < 500 {
            return .clientError
        } else if self >= 500 && self < 600 {
            return .serverError
        } else {
            return .unknown
        }
    }
}

public class Networking {
    static let ErrorDomain = "NetworkingErrorDomain"

    struct FakeRequest {
        let response: Any?
        let statusCode: Int
    }

    /**
     Provides the options for configuring your Networking object with NSURLSessionConfiguration.
     - `Default:` This configuration type manages upload and download tasks using the default options.
     - `Ephemeral:` A configuration type that uses no persistent storage for caches, cookies, or credentials. It's optimized for transferring data to and from your app’s memory.
     - `Background:` A configuration type that allows HTTP and HTTPS uploads or downloads to be performed in the background. It causes upload and download tasks to be performed by the system in a separate process.
     */
    public enum ConfigurationType {
        case `default`, ephemeral, background
    }

    enum RequestType: String {
        case GET, POST, PUT, DELETE
    }

    enum SessionTaskType: String {
        case Data, Upload, Download
    }

    /**
     Sets the rules to serialize your parameters, also sets the `Content-Type` header.
     - `JSON:` Serializes your parameters using `NSJSONSerialization` and sets your `Content-Type` to `application/json`.
     - `FormURLEncoded:` Serializes your parameters using `Percent-encoding` and sets your `Content-Type` to `application/x-www-form-urlencoded`.
     - `MultipartFormData:` Serializes your parameters and parts as multipart and sets your `Content-Type` to `multipart/form-data`.
     - `Custom(String):` Sends your parameters as plain data, sets your `Content-Type` to the value inside `Custom`.
     */
    public enum ParameterType {
        /**
         Serializes your parameters using `NSJSONSerialization` and sets your `Content-Type` to `application/json`.
         */
        case json
        /**
         Serializes your parameters using `Percent-encoding` and sets your `Content-Type` to `application/x-www-form-urlencoded`.
         */
        case formURLEncoded
        /**
         Serializes your parameters and parts as multipart and sets your `Content-Type` to `multipart/form-data`.
         */
        case multipartFormData
        /**
         Sends your parameters as plain data, sets your `Content-Type` to the value inside `Custom`.
         */
        case custom(String)

        func contentType(_ boundary: String) -> String {
            switch self {
            case .json:
                return "application/json"
            case .formURLEncoded:
                return "application/x-www-form-urlencoded"
            case .multipartFormData:
                return "multipart/form-data; boundary=\(boundary)"
            case .custom(let value):
                return value
            }
        }
    }

    enum ResponseType {
        case json
        case data
        case image

        var accept: String? {
            switch self {
            case .json:
                return "application/json"
            default:
                return nil
            }
        }
    }

    /**
     Categorizes a status code.
     - `Informational`: This class of status code indicates a provisional response, consisting only of the Status-Line and optional headers, and is terminated by an empty line.
     - `Successful`: This class of status code indicates that the client's request was successfully received, understood, and accepted.
     - `Redirection`: This class of status code indicates that further action needs to be taken by the user agent in order to fulfill the request.
     - `ClientError:` The 4xx class of status code is intended for cases in which the client seems to have erred.
     - `ServerError:` Response status codes beginning with the digit "5" indicate cases in which the server is aware that it has erred or is incapable of performing the request.
     - `Unknown:` This response status code could be used by Foundation for other types of states, for example when a request gets cancelled you will receive status code -999.
     */
    public enum StatusCodeType {
        case informational, successful, redirection, clientError, serverError, unknown
    }

    private let baseURL: String
    var fakeRequests = [RequestType : [String : FakeRequest]]()
    var token: String?
    var authorizationHeaderValue: String?
    var authorizationHeaderKey = "Authorization"
    var cache: NSCache<AnyObject, AnyObject>
    var configurationType: ConfigurationType

    /**
     Flag used to disable synchronous request when running automatic tests.
     */
    var disableTestingMode = false

    /**
     The boundary used for multipart requests.
     */
    let boundary = String(format: "net.3lvis.networking.%08x%08x", arc4random(), arc4random())

    lazy var session: URLSession = {
        return URLSession(configuration: self.sessionConfiguration())
    }()

    /**
     Base initializer, it creates an instance of `Networking`.
     - parameter baseURL: The base URL for HTTP requests under `Networking`.
     */
    public init(baseURL: String, configurationType: ConfigurationType = .default, cache: NSCache<AnyObject, AnyObject>? = nil) {
        self.baseURL = baseURL
        self.configurationType = configurationType
        self.cache = cache ?? NSCache()
    }

    /**
     Authenticates using Basic Authentication, it converts username:password to Base64 then sets the Authorization header to "Basic \(Base64(username:password))".
     - parameter username: The username to be used.
     - parameter password: The password to be used.
     */
    public func authenticate(username: String, password: String) {
        let credentialsString = "\(username):\(password)"
        if let credentialsData = credentialsString.data(using: .utf8) {
            let base64Credentials = credentialsData.base64EncodedString(options: [])
            let authString = "Basic \(base64Credentials)"

            let config  = self.sessionConfiguration()
            config.httpAdditionalHeaders = [self.authorizationHeaderKey as AnyHashable : authString]
            self.session = URLSession(configuration: config)
        }
    }

    /**
     Authenticates using a Bearer token, sets the Authorization header to "Bearer \(token)".
     - parameter token: The token to be used.
     */
    public func authenticate(token: String) {
        self.token = token
    }

    /**
     Authenticates using a custom HTTP Authorization header.
     - parameter authorizationHeaderKey: Sets this value as the key for the HTTP `Authorization` header
     - parameter authorizationHeaderValue: Sets this value to the HTTP `Authorization` header or to the `headerKey` if you provided that.
     */
    public func authenticate(headerKey: String = "Authorization", headerValue: String) {
        self.authorizationHeaderKey = headerKey
        self.authorizationHeaderValue = headerValue
    }

    /**
     Returns a NSURL by appending the provided path to the Networking's base URL.
     - parameter path: The path to be appended to the base URL.
     - returns: A NSURL generated after appending the path to the base URL.
     */
    public func url(for path: String) -> URL {
        guard let encodedPath = path.encodeUTF8() else { fatalError("Couldn't encode path to UTF8: \(path)") }
        guard let url = URL(string: self.baseURL + encodedPath) else { fatalError("Couldn't create a url using baseURL: \(self.baseURL) and encodedPath: \(encodedPath)") }
        return url
    }

    /**
     Returns the NSURL used to store a resource for a certain path. Useful to find where a download image is located.
     - parameter path: The path used to download the resource.
     - returns: A NSURL where a resource has been stored.
     */
    public func destinationURL(for path: String, cacheName: String? = nil) throws -> URL {
        #if os(tvOS)
            let directory = FileManager.SearchPathDirectory.cachesDirectory
        #else
            let directory = TestCheck.isTesting ? FileManager.SearchPathDirectory.cachesDirectory : FileManager.SearchPathDirectory.documentDirectory
        #endif
        let finalPath = cacheName ?? self.url(for: path).absoluteString
        let replacedPath = finalPath.replacingOccurrences(of: "/", with: "-")
        if let url = URL(string: replacedPath) {
            if let cachesURL = FileManager.default.urls(for: directory, in: .userDomainMask).first {
                #if !os(tvOS)
                    try (cachesURL as NSURL).setResourceValue(true, forKey: URLResourceKey.isExcludedFromBackupKey)
                #endif
                let destinationURL = cachesURL.appendingPathComponent(url.absoluteString)

                return destinationURL
            } else {
                throw NSError(domain: Networking.ErrorDomain, code: 9999, userInfo: [NSLocalizedDescriptionKey : "Couldn't normalize url"])
            }
        } else {
            throw NSError(domain: Networking.ErrorDomain, code: 9999, userInfo: [NSLocalizedDescriptionKey : "Couldn't create a url using replacedPath: \(replacedPath)"])
        }
    }

    /**
     Splits a url in base url and relative path.
     - parameter path: The full url to be splitted.
     - returns: A base url and a relative path.
     */
    public static func splitBaseURLAndRelativePath(for path: String) -> (baseURL: String, relativePath: String) {
        guard let encodedPath = path.encodeUTF8() else { fatalError("Couldn't encode path to UTF8: \(path)") }
        guard let url = URL(string: encodedPath) else { fatalError("Path \(encodedPath) can't be converted to url") }
        guard let baseURLWithDash = URL(string: "/", relativeTo: url)?.absoluteURL.absoluteString else { fatalError("Can't find absolute url of url: \(url)") }
        let index = baseURLWithDash.index(before: baseURLWithDash.endIndex)
        let baseURL = baseURLWithDash.substring(to: index)
        let relativePath = path.replacingOccurrences(of: baseURL, with: "")

        return (baseURL, relativePath)
    }

    /**
     Cancels the request that matches the requestID.
     - parameter requestID: The ID of the request to be cancelled.
     - parameter completion: The completion block to be called when the request is cancelled.
     */
    func cancel(with requestID: String, completion: ((Void) -> Void)? = nil) {
        self.session.getTasksWithCompletionHandler { dataTasks, uploadTasks, downloadTasks in
            var tasks = [URLSessionTask]()
            tasks.append(contentsOf: dataTasks as [URLSessionTask])
            tasks.append(contentsOf: uploadTasks as [URLSessionTask])
            tasks.append(contentsOf: downloadTasks as [URLSessionTask])

            for task in tasks {
                if task.taskDescription == requestID {
                    task.cancel()
                    break
                }
            }

            completion?()
        }
    }

    /**
     Cancels all the current requests.
     - parameter completion: The completion block to be called when all the requests are cancelled.
     */
    public func cancelAllRequests(with completion: ((Void) -> Void)?) {
        self.session.getTasksWithCompletionHandler { dataTasks, uploadTasks, downloadTasks in
            for sessionTask in dataTasks {
                sessionTask.cancel()
            }
            for sessionTask in downloadTasks {
                sessionTask.cancel()
            }
            for sessionTask in uploadTasks {
                sessionTask.cancel()
            }

            TestCheck.testBlock(self.disableTestingMode) {
                completion?()
            }
        }
    }

    /**
     Downloads data from a URL, caching the result.
     - parameter path: The path used to download the resource.
     - parameter completion: A closure that gets called when the download request is completed, it contains  a `data` object and a `NSError`.
     */
    public func downloadData(for path: String, cacheName: String? = nil, completion: @escaping (_ data: Data?, _ error: NSError?) -> Void) {
        self.request(.GET, path: path, cacheName: cacheName, parameterType: nil, parameters: nil, parts: nil, responseType: .data) { response, headers, error in
            completion(response as? Data, error)
        }
    }

    /**
     Retrieves data from the cache or from the filesystem.
     - parameter path: The path where the image is located.
     - parameter cacheName: The cache name used to identify the downloaded data, by default the path is used.
     - parameter completion: A closure that returns the data from the cache, if no data is found it will return nil.
     */
    public func dataFromCache(for path: String, cacheName: String? = nil, completion: @escaping (_ data: Data?) -> Void) {
        self.objectFromCache(for: path, cacheName: cacheName, responseType: .data) { object in
            TestCheck.testBlock(self.disableTestingMode) {
                completion(object as? Data)
            }
        }
    }
}

extension Networking {
    func objectFromCache(for path: String, cacheName: String? = nil, responseType: ResponseType, completion: @escaping (_ object: Any?) -> Void) {
        /*
         Workaround: Remove URL parameters from path. That can lead to writing cached files with names longer than
         255 characters, resulting in error. Another option to explore is to use a hash version of the url if it's
         longer than 255 characters.
         */
        guard let destinationURL = try? self.destinationURL(for: path, cacheName: cacheName) else { fatalError("Couldn't get destination URL for path: \(path) and cacheName: \(cacheName)") }

        if let object = self.cache.object(forKey: destinationURL.absoluteString as AnyObject) {
            completion(object)
        } else if FileManager.default.exists(at: destinationURL) {
            let semaphore = DispatchSemaphore(value: 0)
            var returnedObject: Any?

            DispatchQueue.global(qos: .utility).async {
                let object = self.data(for: destinationURL)
                if responseType == .image {
                    returnedObject = NetworkingImage(data: object)
                } else {
                    returnedObject = object
                }
                if let returnedObject = returnedObject {
                    self.cache.setObject(returnedObject as AnyObject, forKey: destinationURL.absoluteString as AnyObject)
                }

                if TestCheck.isTesting && self.disableTestingMode == false {
                    semaphore.signal()
                } else {
                    completion(returnedObject)
                }
            }

            if TestCheck.isTesting && self.disableTestingMode == false {
                let _ = semaphore.wait(timeout: DispatchTime.distantFuture)
                completion(returnedObject)
            }
        } else {
            completion(nil)
        }
    }

    func data(for destinationURL: URL) -> Data {
        let path = destinationURL.path
        guard let data = FileManager.default.contents(atPath: path) else { fatalError("Couldn't get image in destination url: \(url)") }

        return data
    }

    func sessionConfiguration() -> URLSessionConfiguration {
        switch self.configurationType {
        case .default:
            return URLSessionConfiguration.default
        case .ephemeral:
            return URLSessionConfiguration.ephemeral
        case .background:
            return URLSessionConfiguration.background(withIdentifier: "NetworkingBackgroundConfiguration")
        }
    }

    func fake(_ requestType: RequestType, path: String, fileName: String, bundle: Bundle = Bundle.main) {
        do {
            if let result = try JSON.from(fileName, bundle: bundle) {
                self.fake(requestType, path: path, response: result, statusCode: 200)
            }
        } catch ParsingError.notFound {
            fatalError("We couldn't find \(fileName), are you sure is there?")
        } catch {
            fatalError("Converting data to JSON failed")
        }
    }

    func fake(_ requestType: RequestType, path: String, response: Any?, statusCode: Int) {
        var fakeRequests = self.fakeRequests[requestType] ?? [String : FakeRequest]()
        fakeRequests[path] = FakeRequest(response: response, statusCode: statusCode)
        self.fakeRequests[requestType] = fakeRequests
    }

    @discardableResult
    func request(_ requestType: RequestType, path: String, cacheName: String? = nil, parameterType: ParameterType?, parameters: Any?, parts: [FormDataPart]?, responseType: ResponseType, completion: @escaping (_ response: Any?, _ headers: [AnyHashable : Any], _ error: NSError?) -> ()) -> String {
        var requestID = UUID().uuidString

        if let responses = self.fakeRequests[requestType], let fakeRequest = responses[path] {
            if fakeRequest.statusCode.statusCodeType() == .successful {
                completion(fakeRequest.response, [String : Any](), nil)
            } else {
                let error = NSError(domain: Networking.ErrorDomain, code: fakeRequest.statusCode, userInfo: [NSLocalizedDescriptionKey : HTTPURLResponse.localizedString(forStatusCode: fakeRequest.statusCode)])
                completion(fakeRequest.response, [String : Any](), error)
            }
        } else {
            switch responseType {
            case .json:
                requestID = self.dataRequest(requestType, path: path, cacheName: cacheName, parameterType: parameterType, parameters: parameters, parts: parts, responseType: responseType) { data, headers, error in
                    var returnedError = error
                    var returnedResponse: Any?
                    if let data = data, data.count > 0 {
                        do {
                            returnedResponse = try JSONSerialization.jsonObject(with: data, options: [])
                        } catch let JSONError as NSError {
                            returnedError = JSONError
                        }
                    }
                    TestCheck.testBlock(self.disableTestingMode) {
                        completion(returnedResponse, headers, returnedError)
                    }
                }
                break
            case .data, .image:
                let trimmedPath = path.components(separatedBy: "?").first!

                self.objectFromCache(for: trimmedPath, cacheName: cacheName, responseType: responseType) { object in
                    if let object = object {
                        TestCheck.testBlock(self.disableTestingMode) {
                            completion(object, [String : Any](), nil)
                        }
                    } else {
                        requestID = self.dataRequest(requestType, path: path, cacheName: cacheName, parameterType: parameterType, parameters: parameters, parts: parts, responseType: responseType) { data, headers, error in

                            var returnedResponse: Any?
                            if let data = data, data.count > 0 {
                                guard let destinationURL = try? self.destinationURL(for: trimmedPath, cacheName: cacheName) else { fatalError("Couldn't get destination URL for path: \(path) and cacheName: \(cacheName)") }
                                let _ = try? data.write(to: destinationURL, options: [.atomic])
                                switch responseType {
                                case .data:
                                    self.cache.setObject(data as AnyObject, forKey: destinationURL.absoluteString as AnyObject)
                                    returnedResponse = data
                                    break
                                case .image:
                                    if let image = NetworkingImage(data: data) {
                                        self.cache.setObject(image, forKey: destinationURL.absoluteString as AnyObject)
                                        returnedResponse = image
                                    }
                                    break
                                default:
                                    fatalError("Response Type is different than Data and Image")
                                    break
                                }
                            }
                            TestCheck.testBlock(self.disableTestingMode) {
                                completion(returnedResponse, [String : Any](), error)
                            }
                        }
                    }
                }
                break
            }
        }

        return requestID
    }

    @discardableResult
    func dataRequest(_ requestType: RequestType, path: String, cacheName: String? = nil, parameterType: ParameterType?, parameters: Any?, parts: [FormDataPart]?, responseType: ResponseType, completion: @escaping (_ response: Data?, _ headers: [AnyHashable : Any], _ error: NSError?) -> ()) -> String {
        let requestID = UUID().uuidString
        var request = URLRequest(url: self.url(for: path))
        request.httpMethod = requestType.rawValue

        if let parameterType = parameterType {
            request.addValue(parameterType.contentType(self.boundary), forHTTPHeaderField: "Content-Type")
        }

        if let accept = responseType.accept {
            request.addValue(accept, forHTTPHeaderField: "Accept")
        }

        if let authorizationHeader = self.authorizationHeaderValue {
            request.setValue(authorizationHeader, forHTTPHeaderField: self.authorizationHeaderKey)
        } else if let token = self.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: self.authorizationHeaderKey)
        }

        DispatchQueue.main.async {
            NetworkActivityIndicator.sharedIndicator.visible = true
        }

        var serializingError: NSError?
        if let parameterType = parameterType, let parameters = parameters {
            switch parameterType {
            case .json:
                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: parameters, options: [])
                } catch let error as NSError {
                    serializingError = error
                }
                break
            case .formURLEncoded:
                guard let parametersDictionary = parameters as? [String : Any] else { fatalError("Couldn't convert parameters to a dictionary: \(parameters)") }
                let formattedParameters = parametersDictionary.formURLEncodedFormat()
                request.httpBody = formattedParameters.data(using: .utf8)
                break
            case .multipartFormData:
                var bodyData = Data()

                if let parameters = parameters as? [String : Any] {
                    for (key, value) in parameters {
                        let usedValue: Any = value is NSNull ? "null" : value
                        var body = ""
                        body += "--\(self.boundary)\r\n"
                        body += "Content-Disposition: form-data; name=\"\(key)\""
                        body += "\r\n\r\n\(usedValue)\r\n"
                        bodyData.append(body.data(using: .utf8)!)
                    }
                }

                if let parts = parts {
                    for var part in parts {
                        part.boundary = self.boundary
                        bodyData.append(part.formData as Data)
                    }
                }

                bodyData.append("--\(self.boundary)--\r\n".data(using: .utf8)!)
                request.httpBody = bodyData as Data
                break
            case .custom(_):
                request.httpBody = parameters as? Data
                break
            }
        }

        if let serializingError = serializingError {
            completion(nil, [String : Any](), serializingError)
        } else {
            var connectionError: Error?
            let semaphore = DispatchSemaphore(value: 0)
            var returnedResponse: URLResponse?
            var returnedData: Data?
            var returnedHeaders = [AnyHashable : Any]()

            let session = self.session.dataTask(with: request) { data, response, error in
                returnedResponse = response
                connectionError = error
                returnedData = data

                if let httpResponse = response as? HTTPURLResponse {
                    returnedHeaders = httpResponse.allHeaderFields

                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                        if let data = data, data.count > 0 {
                            returnedData = data
                        }
                    } else {
                        connectionError = NSError(domain: Networking.ErrorDomain, code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey : HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)])
                    }
                }

                if TestCheck.isTesting && self.disableTestingMode == false {
                    semaphore.signal()
                } else {
                    DispatchQueue.main.async {
                        NetworkActivityIndicator.sharedIndicator.visible = false
                    }

                    self.logError(parameterType: parameterType, parameters: parameters, data: returnedData, request: request, response: returnedResponse, error: connectionError as NSError?)
                    completion(returnedData, returnedHeaders, connectionError as NSError?)
                }
            }

            session.taskDescription = requestID
            session.resume()

            if TestCheck.isTesting && self.disableTestingMode == false {
                let _ = semaphore.wait(timeout: DispatchTime.distantFuture)
                self.logError(parameterType: parameterType, parameters: parameters, data: returnedData, request: request as URLRequest, response: returnedResponse, error: connectionError as NSError?)
                completion(returnedData, returnedHeaders, connectionError as NSError?)
            }
        }

        return requestID
    }

    func cancelRequest(_ sessionTaskType: SessionTaskType, requestType: RequestType, url: URL, completion: ((Void) -> Void)?) {
        self.session.getTasksWithCompletionHandler { dataTasks, uploadTasks, downloadTasks in
            var sessionTasks = [URLSessionTask]()
            switch sessionTaskType {
            case .Data:
                sessionTasks = dataTasks
                break
            case .Download:
                sessionTasks = downloadTasks
                break
            case .Upload:
                sessionTasks = uploadTasks
                break
            }

            for sessionTask in sessionTasks {
                if sessionTask.originalRequest?.httpMethod == requestType.rawValue && sessionTask.originalRequest?.url?.absoluteString == url.absoluteString {
                    sessionTask.cancel()
                    break
                }
            }

            completion?()
        }
    }

    func logError(parameterType: ParameterType?, parameters: Any? = nil, data: Data?, request: URLRequest?, response: URLResponse?, error: NSError?) {
        guard let error = error else { return }

        print(" ")
        print("========== Networking Error ==========")
        print(" ")

        let isCancelled = error.code == -999
        if isCancelled {
            if let request = request, let url = request.url {
                print("Cancelled request: \(url.absoluteString)")
                print(" ")
            }
        } else {
            print("*** Request ***")
            print(" ")

            print("Error \(error.code): \(error.description)")
            print(" ")

            if let request = request, let url = request.url {
                print("URL: \(url.absoluteString)")
                print(" ")
            }

            if let headers = request?.allHTTPHeaderFields {
                print("Headers: \(headers)")
                print(" ")
            }

            if let parameterType = parameterType, let parameters = parameters {
                switch parameterType {
                case .json:
                    do {
                        let data = try JSONSerialization.data(withJSONObject: parameters, options: .prettyPrinted)
                        let string = String(data: data, encoding: .utf8)
                        if let string = string {
                            print("Parameters: \(string)")
                            print(" ")
                        }
                    } catch let error as NSError {
                        print("Failed pretty printing parameters: \(parameters), error: \(error)")
                        print(" ")
                    }
                    break
                case .formURLEncoded:
                    guard let parametersDictionary = parameters as? [String : Any] else { fatalError("Couldn't cast parameters as dictionary: \(parameters)") }
                    let formattedParameters = parametersDictionary.formURLEncodedFormat()
                    print("Parameters: \(formattedParameters)")
                    print(" ")
                    break
                default: break
                }
            }

            if let data = data, let stringData = String(data: data, encoding: .utf8) {
                print("Data: \(stringData)")
                print(" ")
            }
            
            if let response = response as? HTTPURLResponse {
                print("*** Response ***")
                print(" ")
                
                print("Headers: \(response.allHeaderFields)")
                print(" ")
                
                print("Status code: \(response.statusCode) — \(HTTPURLResponse.localizedString(forStatusCode: response.statusCode))")
                print(" ")
            }
        }
        print("================= ~ ==================")
        print(" ")
    }
}
