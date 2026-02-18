//
//  AboutViewController.m
//  Processing for iOS
//
//  Created by Frederik Riedel on 17.02.17.
//  Copyright © 2017 Frederik Riedel. All rights reserved.
//

#import "AboutViewController.h"
@import SafariServices;

@interface AboutViewController ()

@end

@implementation AboutViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"About Processing for iOS";

    UIBarButtonItem* done = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    self.navigationItem.rightBarButtonItem = done;

    [self.tier1Button setHidden:YES];
    [self.tier2Button setHidden:YES];
}

-(void) done {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (IBAction)openTwitter:(id)sender {
    SFSafariViewController *sfvc = [[SFSafariViewController alloc] initWithURL:[NSURL URLWithString:@"https://twitter.com/frederikriedel"]];
    [self presentViewController:sfvc animated:YES completion:nil];
}

- (IBAction)buyTier1:(id)sender {
    [self showSupportThankYouAlert];
}

- (IBAction)buyTier2:(id)sender {
    [self showSupportThankYouAlert];
}

- (void)showSupportThankYouAlert {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Thanks for using Processing for iOS" message:@"All features are now free. Enjoy!" preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* ok = [UIAlertAction actionWithTitle:@"Great" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:ok];
    [self presentViewController:alert animated:YES completion:nil];
}

- (IBAction)showTerms:(id)sender {
    SFSafariViewController *sfvc = [[SFSafariViewController alloc] initWithURL:[NSURL URLWithString:@"http://processing-app.org/terms"]];
    [self presentViewController:sfvc animated:YES completion:nil];
}

@end
