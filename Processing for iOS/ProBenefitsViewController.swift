//
//  ProBenefitsViewController.swift
//  Processing for iOS
//
//  Created by Frederik Riedel on 6/10/20.
//  Copyright © 2020 Frederik Riedel. All rights reserved.
//

import UIKit

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

    let proPageVC = ProBenefitsPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)

    private func reloadUI() {
        if isViewLoaded {
            if shownBenefits == .export {
                proPageVC.scrollToIndex(index: 0)
                pageControl.currentPage = 0
            } else {
                proPageVC.scrollToIndex(index: 1)
                pageControl.currentPage = 1
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        proPageVC.pageDelegate = self

        buyButton.layer.cornerRadius = 16
        buyButton.setTitle("All features are already included", for: .normal)

        addChildViewController(proPageVC)
        containerView.addSubview(proPageVC.view)
        proPageVC.view.frame = containerView.bounds
        proPageVC.didMove(toParentViewController: self)

        reloadUI()
    }

    @IBAction func buy(_ sender: ActivityButton) {
        let thxVC = WelcomeToProViewController()
        navigationController?.pushViewController(thxVC, animated: true)
    }

    @IBAction func restore(_ sender: Any) {
        let thxVC = WelcomeToProViewController()
        navigationController?.pushViewController(thxVC, animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        navigationController?.setNavigationBarHidden(true, animated: animated)
        super.viewWillAppear(animated)
    }

    @IBAction func maybeLater(_ sender: Any) {
        dismiss(animated: true)
    }

    @objc static func preloadProductInfo() {
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "finishedLoadingInAppData"), object: nil)
    }

    @objc static func updateExpirationDate() {
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "upgradedToPro"), object: nil)
    }

    static func membershipExpirationDate() -> Date? {
        return nil
    }

    @objc static func completePendingTransactions() {
    }
}

extension ProBenefitsViewController: ProBenefitsPageViewControllerDelegate {
    func didChangePageToIndex(index: Int) {
        pageControl.currentPage = index
    }
}
