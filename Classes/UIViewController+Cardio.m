//
//  UIViewController+Cardio.m
//  icc
//
//  Created by Oleksandr Skrypnyk on 11/19/19.
//

#import "UIViewController+Cardio.h"

@implementation UIViewController (Cardio)

+ (UIViewController *)topViewController {
  UIViewController *topViewController = UIApplication.sharedApplication.keyWindow.rootViewController;
  while (topViewController.presentedViewController) {
    topViewController = topViewController.presentedViewController;
  }
  return topViewController;
}

@end
