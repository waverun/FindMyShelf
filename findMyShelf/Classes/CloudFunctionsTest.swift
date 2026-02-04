import Firebase
import FirebaseFunctions

final class CloudFunctionsTest {
    private lazy var functions = Functions.functions(region: "us-central1")

    func testOpenAIProxy() {
        functions.httpsCallable("openaiProxy").call([:]) { result, error in
            if let error = error as NSError? {
                print("openaiProxy error:", error, error.userInfo)
                return
            }
            print("openaiProxy success:", result?.data ?? "nil")
        }
    }
}

//import FirebaseFunctions
//
//final class CloudFunctionsTest {
//    private let functions = Functions.functions(region: "us-central1")
//
//    func testOpenAIProxy() {
//        functions.httpsCallable("openaiProxy").call([:]) { result, error in
//            if let error = error as NSError? {
//                print("openaiProxy error:", error, error.userInfo)
//                return
//            }
//
//            if let data = result?.data as? [String: Any] {
//                print("openaiProxy success:", data)
//            } else {
//                print("openaiProxy returned unexpected data:", String(describing: result?.data))
//            }
//        }
//    }
//}
