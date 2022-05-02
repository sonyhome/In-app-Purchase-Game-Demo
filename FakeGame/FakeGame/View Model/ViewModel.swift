//
//  ViewModel.swift
//  FakeGame
//
//  Created by Gabriel Theodoropoulos.
//  Copyright © 2019 Appcoda. All rights reserved.
//

import Foundation
import StoreKit

protocol ViewModelDelegate {
    func toggleOverlay(shouldShow: Bool)
    func willStartLongProcess()
    func didFinishLongProcess()
    func showIAPRelatedError(_ error: Error)
    func shouldUpdateUI()
    func didFinishRestoringPurchasesWithZeroProducts()
    func didFinishRestoringPurchasedProducts()
}


class ViewModel {
    
    // MARK: - Properties
    
    var delegate: ViewModelDelegate?
    
    private let model = Model()
    
    var availableExtraLives: Int {
        return model.gameData.extraLives
    }
        
    var availableSuperPowers: Int {
        return model.gameData.superPowers
    }
    
    var didUnlockAllMaps: Bool {
        return model.gameData.didUnlockAllMaps
    }
    
    
    // MARK: - Init
        
    init() {

    }
    
    
    // MARK: - Fileprivate Methods
    
    fileprivate func updateGameDataWithPurchasedProduct(_ product: SKProduct) {
        // Update the proper game data depending on the keyword the
        // product identifier of the give product contains.
        if product.productIdentifier.contains("extra_lives") {
            model.gameData.extraLives = 3
        } else if product.productIdentifier.contains("superpowers") {
            model.gameData.superPowers = 2
        } else {
            model.gameData.didUnlockAllMaps = true
        }
        
        // Store changes.
        _ = model.gameData.update()
        
        // Ask UI to be updated and reload the table view.
        delegate?.shouldUpdateUI()
    }
    
    
    fileprivate func restoreUnlockedMaps() {
        // Mark all maps as unlocked.
        model.gameData.didUnlockAllMaps = true
        
        // Save changes and update the UI.
        _ = model.gameData.update()
        delegate?.shouldUpdateUI()
    }
    
    
    
    // MARK: - Internal Methods
    
    func getProductForItem(at index: Int) -> SKProduct? {
        // Search for a specific keyword depending on the index value.
        let keyword: String
        
        switch index {
        case 0: keyword = "4b9612cf0fd942ad9bdd4c290f33fe76"
        case 1: keyword = "4b9612cf0fd942ad9bdd4c290f33fe77"
        case 2: keyword = "4b9612cf0fd942ad9bdd4c290f33fe78"
        default: keyword = ""
        }
        // Check if there is a product fetched from App Store containing
        // the keyword matching to the selected item's index.
        print("ViewModel DEBUG getProductForItem(\(index) = \(keyword))")
        guard let product = model.getProduct(containing: keyword) else { return nil }
        return product
    }
    
    
    func didConsumeLive() {
        model.gameData.extraLives -= 1
        _ = model.gameData.update()
    }
    
    
    func didConsumeSuperPower() {
        model.gameData.superPowers -= 1
        _ = model.gameData.update()
    }
    
    
    
    // MARK: - Methods To Implement
    
    func viewDidSetup() {
        delegate?.willStartLongProcess()
        
        IAPManager.shared.getProducts { (result) in
            DispatchQueue.main.async {
                self.delegate?.didFinishLongProcess()
                switch result {
                    case .success(let products):
                        print("ViewModel DEBUG viewDidSetup() getProducts() closure => \(products)")
                    IAPManager.shared.debugPrintProduct(products[0])
                    IAPManager.shared.debugPrintProduct(products[1])
                    self.model.products = products
                    case .failure(let error):
                    print("ViewModel DEBUG viewDidSetup() getProducts() closure => error")
                        self.delegate?.showIAPRelatedError(error)
                }
            }
        }
    }
    
    
    func purchase(product: SKProduct) -> Bool {
        if !IAPManager.shared.canMakePayments() {
            return false
        } else {
            delegate?.willStartLongProcess()
            
            IAPManager.shared.buy(product: product) { (result) in
                DispatchQueue.main.async {
                    self.delegate?.didFinishLongProcess()

                    switch result {
                    case .success(_): self.updateGameDataWithPurchasedProduct(product)
                    case .failure(let error): self.delegate?.showIAPRelatedError(error)
                    }
                }
            }
        }

        return true
    }
    
    
    func restorePurchases() {
        delegate?.willStartLongProcess()
        IAPManager.shared.restorePurchases { (result) in
            DispatchQueue.main.async {
                self.delegate?.didFinishLongProcess()

                switch result {
                case .success(let success):
                    if success {
                        self.restoreUnlockedMaps()
                        self.delegate?.didFinishRestoringPurchasedProducts()
                    } else {
                        self.delegate?.didFinishRestoringPurchasesWithZeroProducts()
                    }

                case .failure(let error): self.delegate?.showIAPRelatedError(error)
                }
            }
        }
    }
}
