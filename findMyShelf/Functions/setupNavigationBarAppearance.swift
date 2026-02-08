import UIKit
import SwiftUI

import UIKit

func setupNavigationTitleColor(color: Color) {
    let appearance = UINavigationBarAppearance()
    appearance.configureWithTransparentBackground() // חשוב: לא משנה רקע

    appearance.titleTextAttributes = [
        .foregroundColor: UIColor(color)   // או כל צבע שתרצה
    ]
    appearance.largeTitleTextAttributes = [
        .foregroundColor: UIColor(color)
    ]

    UINavigationBar.appearance().standardAppearance = appearance
    UINavigationBar.appearance().scrollEdgeAppearance = appearance
}

//func setupNavigationBarAppearance(color: Color) {
//    let appearance = UINavigationBarAppearance()
//    appearance.configureWithOpaqueBackground()
//
//    appearance.backgroundColor = UIColor(color)
//    //    appearance.backgroundColor = UIColor(red: 254/255, green: 134/255, blue: 12/255, alpha: 1) // כתום בהיר
//    appearance.titleTextAttributes = [
//        .foregroundColor: UIColor.white
//    ]
//    appearance.largeTitleTextAttributes = [
//        .foregroundColor: UIColor.white
//    ]
//
//    UINavigationBar.appearance().standardAppearance = appearance
//    UINavigationBar.appearance().scrollEdgeAppearance = appearance
//}
