//
//  ViewController.swift
//  SampleApp-Swift
//
//  Copyright (c) 2014 PayPal. All rights reserved.
//

import UIKit

class ViewController: UIViewController, CardIOPaymentViewControllerDelegate {
  @IBOutlet weak var resultLabel: UILabel?

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.
    CardIOUtilities.preload()
  }

  @IBAction func scanCard(sender: AnyObject) {
    guard let cardIOVC = CardIOPaymentViewController(paymentDelegate: self) else { return }
    cardIOVC.modalPresentationStyle = .formSheet
    present(cardIOVC, animated: true, completion: nil)
  }

  func userDidCancel(_ paymentViewController: CardIOPaymentViewController!) {
    resultLabel?.text = "user canceled"
    paymentViewController?.dismiss(animated: true, completion: nil)
  }

  func userDidProvide(_ cardInfo: CardIOCreditCardInfo!, in paymentViewController: CardIOPaymentViewController!) {
    if let info = cardInfo {
      let str = NSString(format: "Received card info.\n Number: %@\n expiry: %02lu/%lu\n cvv: %@.", info.redactedCardNumber, info.expiryMonth, info.expiryYear, info.cvv)
      resultLabel?.text = str as String
    }
    paymentViewController?.dismiss(animated: true, completion: nil)
  }
}
