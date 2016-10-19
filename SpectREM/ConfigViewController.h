//
//  ConfigViewController.h
//  SpectREM
//
//  Created by Mike Daley on 18/10/2016.
//  Copyright © 2016 71Squared Ltd. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "NSViewController+Bindings.h"

@interface ConfigViewController : NSViewController_Bindings

// Display properties
@property (assign) double displayBorderWidth;
@property (assign) double displayCurve;
@property (assign) double displaySaturation;
@property (assign) double displayContrast;
@property (assign) double displayBrightness;

// Sound properties
@property (assign) double soundVolume;
@property (assign) double soundHighPassFilter;
@property (assign) double soundLowPassFilter;

@end
