//import Firebase
//import FirebaseFunctions
//
//final class CloudFunctionsTest {
//    private lazy var functions = Functions.functions(region: "us-central1")
//
//    func testOpenAIProxy() {
//        functions.httpsCallable("openaiProxy").call([:]) { result, error in
//            if let error = error as NSError? {
//                print("openaiProxy error:", error, error.userInfo)
//                return
//            }
//            print("openaiProxy success:", result?.data ?? "nil")
//        }
//    }
//}
