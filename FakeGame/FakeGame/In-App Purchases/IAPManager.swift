//  IAPManager.swift
//  Created by Gabriel Theodoropoulos.
//  Copyright © 2019 Appcoda. All rights reserved.
//  https://www.appcoda.com/in-app-purchases-guide/
//  MIT License

// //    Usage pattern of IAPManager to get the product list from the UI:
// func viewDidSetup() {
//    // Add a UI spinner overlay showing this may take a while
//    delegate?.willStartLongProcess()
//    // Run the async job
//    IAPManager.shared.getProducts { (result) in
//        // Sync to main to access UI
//        DispatchQueue.main.async {
//            // remove the UI spinner overlay
//            self.delegate?.didFinishLongProcess()
//
//            switch result {
//            case .success(let products): self.model.products = products;
//            case .failure(let error): self.delegate?.showIAPRelatedError(error)
//            }
//        }
//    }
//}

import Foundation
import StoreKit

// @brief
// In-App Purchase Manager class
//
// IAPManager must conform to NSObjectProtocol as it adopts the
// SKPaymentTransactionObserver protocol, hence inherits NSObject
class IAPManager: NSObject {
    /// /// SINGLETON CLASS ///
    // Enforce IAPManager to be a singleton class
    static let shared = IAPManager()
    private override init()
    {
        super.init()
    }

    /// /// ERROR HANDLING ///
    // Gracefull custom error management on failures
    enum IAPManagerError: Error
    {
        case noProductIDsFound
        case noProductsFound // No IAP products
        case paymentWasCancelled // User cancelled
        case productRequestFailed // IAP cannot contact App Store to get product list
    }

    /// /// GET PRODUCT LIST ///
    // @brief Properties
    // Escaped handler (closure) that processes product list received from the App Store
    var onReceiveProductsHandler: ((Result<[SKProduct], IAPManagerError>) -> Void)?
        
    // @brief Helper method
    // Read in-app product list from the IAP_ProductIDs.plist file
    // and return an array of product Strings that may be nil (can't access file)
    // or empty (plist content can't be converted to an array of strings).
    fileprivate func getProductIDs() -> [String]?
    {
        guard let url = Bundle.main.url(
            forResource: "IAP_ProductIDs",
            withExtension: "plist")
        else { return nil }
        
        do {
            // Fetch plist
            let data : Data = try Data(contentsOf: url)
            // Convert plist into an array.
            // PropertyListSerialization helper class encodes/decodes plists.
            let productIDs : [String]? = try PropertyListSerialization.propertyList(
                from: data,
                options: .mutableContainersAndLeaves,
                format: nil) as? [String] ?? []
            return productIDs
        } catch {
            print(error.localizedDescription)
            return nil
        }
    } // func getProductIDs
    
    // @brief Helper method
    // Format the price as a string with currency
    // /// USAGE: ///
    // guard let price = IAPManager.shared.getPriceFormatted(for: product) else { return }
    func getPriceFormatted(for product: SKProduct) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceLocale
        return formatter.string(from: product.price)
    }
    
    // @brief
    // Fetch IAP Products from the Apple Store (with their properties like pricing)
    // The Result type to the closure/handler is either .failure or .success
    // /// USAGE: ///
    //    var products = [SKProduct]()
    //    func viewDidSetup() {
    //        delegate?.willStartLongProcess()
    //        IAPManager.shared.getProducts { (result) in
    //            DispatchQueue.main.async {
    //                self.delegate?.didFinishLongProcess()
    //                switch result {
    //                    case .success(let products): self.model.products = products
    //                    case .failure(let error): self.delegate?.showIAPRelatedError(error)
    //   }   }    }   }
    func getProducts(
        withHandler productsReceiveHandler: @escaping (_ result: Result<[SKProduct], IAPManagerError>) -> Void
    ) {
        // Save the handler (closure) that processes the Apple Store query results
        self.onReceiveProductsHandler = productsReceiveHandler

        // Get the product identifiers from the plist file.
        guard let productIDs : [String] = getProductIDs()
        else {
            // the array is nil
            productsReceiveHandler(.failure(.noProductIDsFound))
            return
        }

        let productIDsSet : Set<String> = Set(productIDs)
        
        // The App Store is available through SKProductsRequest which conforms to
        // the SKRequestDelegate protocol. The IAPManager can become a delegate
        // by being exended to conform to the SKProductsRequestDelegate protocol
        let request = SKProductsRequest(productIdentifiers: productIDsSet)
        request.delegate = self

        // Query assynchronously the App Store for the product list.
        request.start()
    } // func getProducts
    
    
    /// /// PURCHASE PRODUCT ///
    // A purchase is a SKPaymentTransaction transaction managed by a SKPaymentQueue
    // which communicates with the App Store and handles the payment process. A built-in
    // UI appears. A SKPaymentTransactionObserver is added to the queue to monitor purchases.
    
    // @brief Properties
    // Escaped handler (closure) that processes product purchase from the App Store
    var onBuyProductHandler: ((Result<Bool, Error>) -> Void)?
    var totalRestoredPurchases = 0

    //  Add/remove IAPManager as a payment transaction observer to the payment queue
    // /// USAGE: ///
    // Must be called early enough in the app (for ex in AppDelegate.application())
    // and close at the end (in AppDelegate.applicationWillTerminate())
    func startObserving() {
        SKPaymentQueue.default().add(self)
    }
    func stopObserving() {
        SKPaymentQueue.default().remove(self)
    }
    
    // Check in-app purchases are enabled for the current user
    func canMakePayments() -> Bool {
        return SKPaymentQueue.canMakePayments()
    }

    // Implement a purchase action used by a UI purchase button
    // /// USAGE: ///
    // func purchase(product: SKProduct) -> Bool {
    //    if !IAPManager.shared.canMakePayments() {
    //        return false
    //    } else {
    //        delegate?.willStartLongProcess() // UI spinning circle hint
    //        IAPManager.shared.buy(product: product)  { (result) in
    //            DispatchQueue.main.async {
    //                self.delegate?.didFinishLongProcess() // Clear UI hint
    //                switch result {
    //                case .success(_): self.updateUiWithPurchasedProduct(product)
    //                case .failure(let error): self.delegate?.showIAPRelatedError(error)
    //    }   }   }   }
    func buy(
        product: SKProduct,
        withHandler closure: @escaping ((_ result: Result<Bool, Error>) -> Void)
    ) {
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)

        // Save the completion handler for the SKPaymentTransactionObserver
        onBuyProductHandler = closure
    }
    
    // /// USAGE: ///
    //func restorePurchases() {
    //    delegate?.willStartLongProcess()
    //    IAPManager.shared.restorePurchases { (result) in
    //        DispatchQueue.main.async {
    //            self.delegate?.didFinishLongProcess()
    //            switch result {...
    //}   }   }   }
    func restorePurchases(withHandler handler: @escaping ((_ result: Result<Bool, Error>) -> Void)) {
        onBuyProductHandler = handler
        totalRestoredPurchases = 0
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    
} // class IAPManager



/// /// PURCHASE PRODUCT ///

// @brief
// Extend IAPManager to be a payment observer
extension IAPManager: SKPaymentTransactionObserver {
    // @brief
    // Called when the state of payment transactions change in the payment queue.
    // When a transaction is complete it calls the payment closure set by the user
    func paymentQueue(
        _ queue: SKPaymentQueue,
        updatedTransactions transactions: [SKPaymentTransaction]
    ) {
        // There could be more than one payment in flight
        transactions.forEach { (transaction) in
            switch transaction.transactionState
            {
            case .purchased:
                // Call the closure and mark transaction fully finished
                onBuyProductHandler?(.success(true))
                SKPaymentQueue.default().finishTransaction(transaction)
                
            case .restored:
                // Call the closure and mark transaction fully finished
                totalRestoredPurchases += 1
                SKPaymentQueue.default().finishTransaction(transaction)
                
            case .failed:
                // Call the closure with an error and mark transaction fully finished
                if let error = transaction.error as? SKError
                {
                    if error.code != .paymentCancelled {
                        onBuyProductHandler?(.failure(error))
                    } else {
                        // If payment is cancelled we pass in our own error code
                        onBuyProductHandler?(.failure(IAPManagerError.paymentWasCancelled))
                    }
                    print("IAP Error:", error.localizedDescription)
                }
                
                SKPaymentQueue.default().finishTransaction(transaction)
                
            case .deferred, .purchasing:
                break
                
            @unknown default: break
            }
        }
    }
    
    
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        if totalRestoredPurchases != 0 {
            onBuyProductHandler?(.success(true))
        } else {
            print("IAP: No purchases to restore!")
            onBuyProductHandler?(.success(false))
        }
    }
    
    
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        if let error = error as? SKError {
            if error.code != .paymentCancelled {
                print("IAP Restore Error:", error.localizedDescription)
                onBuyProductHandler?(.failure(error))
            } else {
                onBuyProductHandler?(.failure(IAPManagerError.paymentWasCancelled))
            }
        }
    }
} // extension IAPManager: SKPaymentTransactionObserver



/// /// GET PRODUCT LIST ///

// @brief
// Extend IAPManager to the SKProductsRequestDelegate so it can become a delegate
// that processes the assynchronous App Store product list request using
// SKProductsRequest() in getProducts()
extension IAPManager: SKProductsRequestDelegate {
    // @brief
    // Assyncrhonous handler (closure) called once the App Store sends back a response.
    // Pre-processes the results and returns them to the IAPManager's handler.
    func productsRequest(
        _ request: SKProductsRequest,
        didReceive response: SKProductsResponse)
    {
        // Get the available products contained in the response.
        let products : [SKProduct] = response.products
        // @note: response.invalidProductIdentifiers lists products that are not valid to purchased.
        
        // Pass the results to the IAPManager handler
        if products.count > 0 {
            self.onReceiveProductsHandler?(.success(products))
        } else {
            // No matching products were found in the App Store.
            self.onReceiveProductsHandler?(.failure(.noProductsFound))
        }
    }
    
    // @brief
    // Handle the case where the App Store request failed
    func request(_ request: SKRequest, didFailWithError error: Error)
    {
        self.onReceiveProductsHandler?(.failure(.productRequestFailed))
    }
    
    // @brief
    // OPTIONAL - add custom logic to apply when a product request is finished
    func requestDidFinish(_ request: SKRequest) { }
    
} // extension IAPManager: SKProductsRequestDelegate



/// /// ERROR HANDLING ///

// @brief
// IAPManager error manager extension for localizedDescription
extension IAPManager.IAPManagerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noProductIDsFound: return "No In-App Purchase product identifiers were found."
        case .noProductsFound: return "No In-App Purchases were found."
        case .productRequestFailed: return "Unable to fetch available In-App Purchase products from the Apple App Store at the moment."
        case .paymentWasCancelled: return "In-App Purchase process was cancelled."
        }
    }
}
