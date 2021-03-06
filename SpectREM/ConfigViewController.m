//
//  ConfigViewController.m
//  SpectREM
//
//  Created by Mike Daley on 18/10/2016.
//  Copyright © 2016 71Squared Ltd. All rights reserved.
//

#import "ConfigViewController.h"

@interface ConfigViewController ()

@end

@implementation ConfigViewController

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
        
        [preferences addObserver:self forKeyPath:@"displayBorderWidth" options:NSKeyValueObservingOptionNew context:NULL];
        [preferences addObserver:self forKeyPath:@"displayCurve" options:NSKeyValueObservingOptionNew context:NULL];
        [preferences addObserver:self forKeyPath:@"displaySaturation" options:NSKeyValueObservingOptionNew context:NULL];
        [preferences addObserver:self forKeyPath:@"displayContrast" options:NSKeyValueObservingOptionNew context:NULL];
        [preferences addObserver:self forKeyPath:@"displayBrightness" options:NSKeyValueObservingOptionNew context:NULL];
        [preferences addObserver:self forKeyPath:@"displayVignetteX" options:NSKeyValueObservingOptionNew context:NULL];
        [preferences addObserver:self forKeyPath:@"displayVignetteY" options:NSKeyValueObservingOptionNew context:NULL];
        
        [preferences addObserver:self forKeyPath:@"soundVolume" options:NSKeyValueObservingOptionNew context:NULL];
        [preferences addObserver:self forKeyPath:@"soundLowPassFilter" options:NSKeyValueObservingOptionNew context:NULL];
        [preferences addObserver:self forKeyPath:@"soundHighPassFilter" options:NSKeyValueObservingOptionNew context:NULL];
        
        // Apply default values
        NSString *userDefaultsPath = [[NSBundle mainBundle] pathForResource:@"Defaults" ofType:@"plist"];
        NSDictionary *userDefaults = [NSDictionary dictionaryWithContentsOfFile:userDefaultsPath];
        [preferences registerDefaults:userDefaults];
        NSUserDefaultsController *defaultsController = [NSUserDefaultsController sharedUserDefaultsController];
        [defaultsController setInitialValues:userDefaults];
    }
    
    return self;
}

- (void)resetPreferences
{
    NSWindow *window = [[NSApplication sharedApplication] mainWindow];
    
    NSAlert *alert = [NSAlert new];
    alert.informativeText = @"Are you sure you want to reset your preferences?";
    [alert addButtonWithTitle:@"No"];
    [alert addButtonWithTitle:@"Yes"];
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertSecondButtonReturn)
        {
            NSUserDefaultsController *defaultsController = [NSUserDefaultsController sharedUserDefaultsController];
            [defaultsController revertToInitialValues:[self observableFloatKeys]];
        }
    }];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    for (NSString *key in [self observableFloatKeys]) {
        if ([keyPath isEqualToString:key])
        {
            [self setValue:change[NSKeyValueChangeNewKey] forKey:key];
        }
    }
}

- (NSArray *)observableFloatKeys
{
    return @[
             @"displayBorderWidth",
             @"displayCurve",
             @"displaySaturation",
             @"displayBrightness",
             @"displayContrast",
             @"displayVignetteX",
             @"displayVignetteY",
             @"soundVolume",
             @"soundLowPassFilter",
             @"soundHighPassFilter"
             ];
}

@end
