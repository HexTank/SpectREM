//
//  ViewController.m
//  SpectREM
//
//  Created by Mike Daley on 14/10/2016.
//  Copyright © 2016 71Squared Ltd. All rights reserved.
//

#import <IOKit/hid/IOHIDLib.h>

#import "EmulationViewController.h"
#import "EmulationScene.h"
#import "ConfigViewController.h"
#import "EmulationView.h"

#import "ZXSpectrum48.h"
#import "ZXSpectrum128.h"

NS_ENUM(NSUInteger, MachineType)
{
    eZXSpectrum48 = 0,
    eZXSpectrum128
};

#pragma mark - Private Interface

@interface EmulationViewController () <NSWindowDelegate>



@end

#pragma mark - Implementation

@implementation EmulationViewController
{
    EmulationScene          *_emulationScene;
    ZXSpectrum              *_machine;
    ConfigViewController    *_configViewController;
    NSPopover               *_configPopover;
    IOHIDManagerRef         _hidManager;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _emulationScene = (EmulationScene *)[SKScene nodeWithFileNamed:@"EmulationScene"];
    _emulationScene.scaleMode = SKSceneScaleModeFill;
    
    _configViewController = [ConfigViewController new];
    _configPopover = [NSPopover new];
    _configPopover.contentViewController = _configViewController;
    _configPopover.behavior = NSPopoverBehaviorTransient;
//    _configPopover.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];

    [self setupViewConstraints];
    
    // Ensure that the view is the same size as the parent window before presenting the scene. Not
    // doing this causes the view to appear breifly at the size it is defined in the story board.
    self.skView.frame = self.skView.window.frame;
    
    // Present the scene
    [self.skView presentScene:_emulationScene];

    [self setupLocalBindings];
    [self setupMachineBindings];
    [self setupSceneBindings];
    [self switchToMachine:_configViewController.currentMachineType];
    
    [_machine start];
    
    [self setupGamepad];
    
}

- (void)setupSceneBindings
{
    [_emulationScene bind:@"displayCurve" toObject:_configViewController withKeyPath:@"displayCurve" options:nil];
    [_emulationScene bind:@"displaySaturation" toObject:_configViewController withKeyPath:@"displaySaturation" options:nil];
    [_emulationScene bind:@"displayContrast" toObject:_configViewController withKeyPath:@"displayContrast" options:nil];
    [_emulationScene bind:@"displayBrightness" toObject:_configViewController withKeyPath:@"displayBrightness" options:nil];
    [_emulationScene bind:@"displayShowVignette" toObject:_configViewController withKeyPath:@"displayShowVignette" options:nil];
    [_emulationScene bind:@"displayVignetteX" toObject:_configViewController withKeyPath:@"displayVignetteX" options:nil];
    [_emulationScene bind:@"displayVignetteY" toObject:_configViewController withKeyPath:@"displayVignetteY" options:nil];
}

- (void)setupMachineBindings
{
    [_machine bind:@"displayBorderWidth" toObject:_configViewController withKeyPath:@"displayBorderWidth" options:nil];
    [_machine bind:@"soundHighPassFilter" toObject:_configViewController withKeyPath:@"soundHighPassFilter" options:nil];
    [_machine bind:@"soundLowPassFilter" toObject:_configViewController withKeyPath:@"soundLowPassFilter" options:nil];
    [_machine bind:@"soundVolume" toObject:_configViewController withKeyPath:@"soundVolume" options:nil];
}

- (void)setupLocalBindings
{
    [_configViewController addObserver:self forKeyPath:@"currentMachineType" options:NSKeyValueObservingOptionNew context:NULL];
}

- (void)removeBindings
{
    [_emulationScene unbind:@"displayCurve"];
    [_emulationScene unbind:@"displaySaturation"];
    [_emulationScene unbind:@"displayContrast"];
    [_emulationScene unbind:@"displayCurve"];
    [_emulationScene unbind:@"displayBrightness"];
    [_emulationScene unbind:@"displayVignetteX"];
    [_emulationScene unbind:@"displayVignetteY"];
    
    [_machine unbind:@"displayBorderWidth"];
    [_machine unbind:@"soundHighPassFilter"];
    [_machine unbind:@"soundLowPassFilter"];
    [_machine unbind:@"soundVolume"];
}

#pragma mark - Observers

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"currentMachineType"])
    {
        [self switchToMachine:[[change valueForKey:NSKeyValueChangeNewKey] unsignedIntegerValue]];
    }
}

#pragma mark - View events

- (void)viewDidLayout
{
    [_emulationScene sceneViewSizeChanged:self.view.frame.size];
}

#pragma mark - Constraints

- (void)setupViewConstraints
{
    [self.view setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.view.superview addConstraint:[NSLayoutConstraint constraintWithItem:self.view
                                                                    attribute:NSLayoutAttributeTop
                                                                    relatedBy:NSLayoutRelationEqual
                                                                       toItem:self.view.superview
                                                                    attribute:NSLayoutAttributeTop
                                                                   multiplier:1
                                                                     constant:0]];
    
    [self.view.superview addConstraint:[NSLayoutConstraint constraintWithItem:self.view
                                                                    attribute:NSLayoutAttributeRight
                                                                    relatedBy:NSLayoutRelationEqual
                                                                       toItem:self.view.superview
                                                                    attribute:NSLayoutAttributeRight
                                                                   multiplier:1
                                                                     constant:0]];

    [self.view.superview addConstraint:[NSLayoutConstraint constraintWithItem:self.view
                                                                    attribute:NSLayoutAttributeBottom
                                                                    relatedBy:NSLayoutRelationEqual
                                                                       toItem:self.view.superview
                                                                    attribute:NSLayoutAttributeBottom
                                                                   multiplier:1
                                                                     constant:0]];

    [self.view.superview addConstraint:[NSLayoutConstraint constraintWithItem:self.view
                                                                    attribute:NSLayoutAttributeLeft
                                                                    relatedBy:NSLayoutRelationEqual
                                                                       toItem:self.view.superview
                                                                    attribute:NSLayoutAttributeLeft
                                                                   multiplier:1
                                                                     constant:0]];
}

#pragma mark - Keyboard events

- (void)flagsChanged:(NSEvent *)event
{
    [_machine flagsChanged:event];
}

- (void)updateEmulationDisplayTextureWithImage:(SKTexture *)emulationDisplayTexture
{
    _emulationScene.emulationDisplaySprite.texture = emulationDisplayTexture;
}

#pragma mark - UI Actions

- (IBAction)setAspectFitMode:(id)sender
{
    _emulationScene.scaleMode = SKSceneScaleModeAspectFit;
}

- (IBAction)setFillMode:(id)sender
{
    _emulationScene.scaleMode = SKSceneScaleModeFill;
}

- (IBAction)machineRestart:(id)sender
{
    dispatch_sync(_machine.emulationQueue, ^{
        [self.view.window setTitle:@"SpectREM"];
        [_machine reset];
    });
}

- (IBAction)configButtonPressed:(id)sender
{
    CGRect rect = [(NSButton *)sender frame];
    [_configPopover showRelativeToRect:rect ofView:self.view preferredEdge:NSRectEdgeMaxY];
}

- (IBAction)openFile:(id)sender
{
    NSOpenPanel *openPanel = [NSOpenPanel new];
    openPanel.canChooseDirectories = NO;
    openPanel.allowsMultipleSelection = NO;
    openPanel.allowedFileTypes = @[@"sna", @"z80"];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [openPanel beginSheetModalForWindow:self.view.window completionHandler:^(NSInteger result) {
            if (result == NSModalResponseOK)
            {
                [self loadFileWithURL:openPanel.URLs[0]];
                [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:openPanel.URLs[0]];
            }
        }];
    });
}

- (void)loadFileWithURL:(NSURL *)url
{
    [self.view.window setTitle:[NSString stringWithFormat:@"SpectREM - %@", [url.path lastPathComponent]]];
    [_machine loadSnapshotWithPath:url.path];
}

- (IBAction)resetPreferences:(id)sender
{
    [_configViewController resetPreferences];
}

- (IBAction)switchMachine:(id)sender
{
    NSAlert *alert = [NSAlert new];
    alert.informativeText = @"Are you sure you want to switch machines?";
    [alert addButtonWithTitle:@"No"];
    [alert addButtonWithTitle:@"Yes"];
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertSecondButtonReturn)
        {
            [self switchToMachine:[sender tag]];
        }
    }];
}

- (void)switchToMachine:(NSUInteger)machineType
{
    [_machine stop];
    [self removeBindings];
    _machine = nil;
    switch (machineType) {
        default:
        case eZXSpectrum48:
            _machine = [[ZXSpectrum48 alloc] initWithEmulationViewController:self];
            break;
        case eZXSpectrum128:
            _machine = [[ZXSpectrum128 alloc] initWithEmulationViewController:self];
            break;
    }
    _emulationScene.keyboardDelegate = _machine;
    [self setupMachineBindings];
    [self setupSceneBindings];
}

- (IBAction)setWindowSize:(id)sender
{
    [self.view.animator setFrameSize:(NSSize){320, 156}];
}

#pragma mark - USB Controllers

void gamepadWasAdded(void* inContext, IOReturn inResult, void* inSender, IOHIDDeviceRef device) {
    NSLog(@"Gamepad was plugged in");
}

void gamepadWasRemoved(void* inContext, IOReturn inResult, void* inSender, IOHIDDeviceRef device) {
    NSLog(@"Gamepad was unplugged");
}

void gamepadAction(void* inContext, IOReturn inResult, void* inSender, IOHIDValueRef value) {
    NSLog(@"Gamepad talked!");
    IOHIDElementRef element = IOHIDValueGetElement(value);
    NSLog(@"Element: %@", element);
    int elementValue = (int)IOHIDValueGetIntegerValue(value);
    NSLog(@"Element value: %i", elementValue);
}

-(void) setupGamepad {
    _hidManager = IOHIDManagerCreate( kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    NSMutableDictionary* criterion = [[NSMutableDictionary alloc] init];
    [criterion setObject: [NSNumber numberWithInt: kHIDPage_GenericDesktop] forKey: (NSString*)CFSTR(kIOHIDDeviceUsagePageKey)];
    //    [criterion setObject: [NSNumber numberWithInt: kHIDUsage_GD_GamePad] forKey: (NSString*)CFSTR(kIOHIDDeviceUsageKey)];
    IOHIDManagerSetDeviceMatching(_hidManager, (CFDictionaryRef)criterion);
    IOHIDManagerRegisterDeviceMatchingCallback(_hidManager, gamepadWasAdded, (void*)self);
    IOHIDManagerRegisterDeviceRemovalCallback(_hidManager, gamepadWasRemoved, (void*)self);
    IOHIDManagerScheduleWithRunLoop(_hidManager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    //    IOReturn tIOReturn = IOHIDManagerOpen(hidManager, kIOHIDOptionsTypeNone);
    IOHIDManagerRegisterInputValueCallback(_hidManager, gamepadAction, (void*)self);
}

@end

