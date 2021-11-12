//
//  ProBenefitsViewController.swift
//  Processing for iOS
//
//  Created by Frederik Riedel on 6/10/20.
//  Copyright © 2020 Frederik Riedel. All rights reserved.
//

import UIKit
import SwiftyStoreKit

@objc enum Benefit: Int {
    case export, codeFix
}

class ProBenefitsViewController: UIViewController {
    

    @IBOutlet weak var containerView: UIView!
    
    @IBOutlet weak var pageControl: UIPageControl!
    
    @IBOutlet weak var buyButton: ActivityButton!
    
    @objc var shownBenefits = Benefit.export {
        didSet {
            reloadUI()
        }
    }
    
    private func reloadUI() {
        if isViewLoaded {
            if shownBenefits == .export {
                proPageVC.scrollToIndex(index: 0)
                self.pageControl.currentPage = 0
            } else {
                proPageVC.scrollToIndex(index: 1)
                self.pageControl.currentPage = 1
            }
        }
    }
    
    let proPageVC = ProBenefitsPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        proPageVC.pageDelegate = self
        
        buyButton.layer.cornerRadius = 16
        
        addChildViewController(proPageVC)
        
        containerView.addSubview(proPageVC.view)
        proPageVC.view.frame = containerView.bounds
        proPageVC.didMove(toParentViewController: self)
        
        reloadUI()
        // Do any additional setup after loading the view.
    }
    
    @IBAction func buy(_ sender: ActivityButton) {
        
        sender.showLoading()
        if let membershipProduct = ProBenefitsViewController.products.first {
            
            purchaseProMembership(product: membershipProduct) { (result) in
                
                sender.hideLoading()
                
                switch result {
                case .success(let purchaseDetails):
                    ProBenefitsViewController.updateExpirationDate()
                    let thxVC = WelcomeToProViewController()
                    self.navigationController?.pushViewController(thxVC, animated: true)
                case .error(error: let error):
                    print(error)
                    let alert = UIAlertController(title: "Error Occured", message: error.localizedDescription, preferredStyle: .alert)
                    let cancel = UIAlertAction(title: "Cancel", style: .cancel)
                    alert.addAction(cancel)
                    
                    self.present(alert, animated: true)
                }
                
            }
        }
    }
    
    @IBAction func restore(_ sender: Any) {
        
        self.buyButton.showLoading()
        ProBenefitsViewController.restorePurchases { (results) in
            
            if results.restoredPurchases.count > 0 {
                ProBenefitsViewController.updateExpirationDate()
                let thxVC = WelcomeToProViewController()
                self.navigationController?.pushViewController(thxVC, animated: true)
            }
        }
        
    }

    
    
    override func viewWillAppear(_ animated: Bool) {
        navigationController?.setNavigationBarHidden(true, animated: animated)
        super.viewWillAppear(animated)
    }
    
    @IBAction func maybeLater(_ sender: Any) {
        dismiss(animated: true)
    }
    
//    @objc static var isCurrentlySubscribed: Bool {
//        return currentMembershipStatus == .subscribed
//    }
    
    private static let productIds: Set = ["io.frogg.processing.pro"]
    
    static var products = [SKProduct]()
    
    @objc static func preloadProductInfo() {
        SwiftyStoreKit.retrieveProductsInfo(productIds) { result in
            ProBenefitsViewController.products = Array(result.retrievedProducts)
            print(products)
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "finishedLoadingInAppData"), object: nil)
        }
    }
    
    func purchaseProMembership(product: SKProduct, completion: @escaping (PurchaseResult) -> Void) {
        SwiftyStoreKit.purchaseProduct(product, quantity: 1, atomically: true) { result in
            print(result)
            completion(result)
            // on success
        }
    }
    
    static func restorePurchases(completion: @escaping (RestoreResults) -> Void) {
        SwiftyStoreKit.restorePurchases(atomically: true) { results in
            completion(results)
        }
    }
    
    @objc static func updateExpirationDate() {
        
        var verificationType = AppleReceiptValidator.VerifyReceiptURLType.production
        
        #if DEBUG
        verificationType = AppleReceiptValidator.VerifyReceiptURLType.sandbox
        #endif
        
        
        let appleValidator = AppleReceiptValidator(service: verificationType, sharedSecret: "8b73ae394efe4d4aa96306dc11d48c5a")
        SwiftyStoreKit.verifyReceipt(using: appleValidator) { result in
            switch result {
            case .success(let receipt):
                
                // Verify the purchase of a Subscription
                var expirationDates = [Date]()
                
                self.productIds.forEach({ (productId) in
                    let purchaseResult = SwiftyStoreKit.verifySubscription(
                        ofType: .autoRenewable,
                        productId: productId,
                        inReceipt: receipt)
                    
                    switch purchaseResult {
                    case .purchased(_, let items):
                        let expireDate = self.getLatestExpireDate(fromItems: items)
                        expirationDates.append(expireDate)
                    case .expired(_, let items):
                        let expireDate = self.getLatestExpireDate(fromItems: items)
                        expirationDates.append(expireDate)
                    case .notPurchased:
                        print("The user has never purchased \(productId)")
                    }
                })
                
                NotificationCenter.default.post(name: NSNotification.Name(rawValue: "finishedLoadingInAppData"), object: nil)
                
                if expirationDates.count > 0 {
                    expirationDates.sort()
                    expirationDates.reverse()
                    let defaults = UserDefaults.standard
                    let membershipInformation = ["expirationDate": expirationDates.first!]
                    defaults.set(membershipInformation, forKey: "membershipStatus")
                    defaults.synchronize()
                    NotificationCenter.default.post(name: NSNotification.Name(rawValue: "upgradedToPro"), object: nil)
                }
                
            case .error(let error):
                print("Receipt verification failed: \(error)")
            }
        }
    }
    
    static func membershipExpirationDate() -> Date? {
        let defaults = UserDefaults.standard
        
        if let membershipInformation = defaults.object(forKey: "membershipStatus") as? [String: Any] {
            if let expirationDate = membershipInformation["expirationDate"] as? Date {
                return expirationDate
            }
        }
        
        return nil
    }
    
//    enum MembershipStatus {
//        case notPurchased, subscribed, expired
//    }
//    
//    static var currentMembershipStatus: MembershipStatus {
//        
//        if CommandLine.arguments.contains("-subscribed") {
//            return .subscribed
//        }
//        
//        #if DEBUG
//        if CommandLine.arguments.contains("-expired") {
//            return .expired
//        }
//        if !CommandLine.arguments.contains("-real") {
//            return .subscribed
//        }
//        #endif
//        
//        if let expirationDate = membershipExpirationDate() {
//            // give one week of grace period
//            var gracePeriod = TimeInterval.week
//            #if DEBUG
//            gracePeriod = 0
//            #endif
//            if Date().timeIntervalSince(expirationDate) < gracePeriod {
//                return .subscribed
//            } else {
//                return .expired
//            }
//        }
//        return .notPurchased
//    }
    
    @objc static func completePendingTransactions() {
        SwiftyStoreKit.shouldAddStorePaymentHandler = { (_ payment: SKPayment, _ product: SKProduct) in
            
            //            let inAppViewController = NewProMemberViewController.initFromStoryboard()
            //
            //            let navController = UINavigationController(rootViewController: inAppViewController)
            //            navController.navigationBar.isHidden = true
            //            UIApplication.shared.keyWindow?.rootViewController?.present(navController, animated: true)
            
            return true
        }
        
        SwiftyStoreKit.completeTransactions(atomically: false) { purchases in
            for purchase in purchases {
                switch purchase.transaction.transactionState {
                case .purchased, .restored:
                    if purchase.needsFinishTransaction {
                        // Deliver content from server, then:
                        SwiftyStoreKit.finishTransaction(purchase.transaction)
                    }
                // Unlock content
                case .failed, .purchasing, .deferred:
                    break // do nothing
                }
            }
        }
    }
    
    private static func getLatestExpireDate(fromItems items: [ReceiptItem]) -> Date {
        var latestExpirationDate = Date(timeIntervalSince1970: 0)
        for item in items {
            if let expirationDate = item.subscriptionExpirationDate {
                if expirationDate > latestExpirationDate {
                    latestExpirationDate = expirationDate
                }
            }
        }
        return latestExpirationDate
    }
}


extension ProBenefitsViewController: ProBenefitsPageViewControllerDelegate {
    func didChangePageToIndex(index: Int) {
        self.pageControl.currentPage = index
    }
}
