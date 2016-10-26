//
//  ViewController.m
//  SpectREM
//
//  Created by Mike Daley on 14/10/2016.
//  Copyright © 2016 71Squared Ltd. All rights reserved.
//

#import <GameController/GameController.h>
#import <IOKit/hid/IOHIDLib.h>

#import "EmulationViewController.h"
#import "EmulationScene.h"
#import "ZXSpectrum48.h"
#import "ConfigViewController.h"
#import "EmulationView.h"

#pragma mark - Private Interface

@interface EmulationViewController () <NSWindowDelegate>

@end

#pragma mark - Implementation

@implementation EmulationViewController
{
    EmulationScene *_emulationScene;
    ZXSpectrum48 *_machine;
    ConfigViewController *_configViewController;
    NSPopover *_configPopover;
    NSTrackingArea *trackingArea;
    BOOL _firstUpdate;
    IOHIDManagerRef hidManager;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _emulationScene = (EmulationScene *)[SKScene nodeWithFileNamed:@"EmulationScene"];
    _emulationScene.scaleMode = SKSceneScaleModeFill;
    
    _configViewController = [ConfigViewController new];
    _configPopover = [NSPopover new];
    _configPopover.contentViewController = _configViewController;
    _configPopover.behavior = NSPopoverBehaviorTransient;
    
    //Setup the machine to be emulated
    _machine = [[ZXSpectrum48 alloc] initWithEmulationViewController:self];
    _emulationScene.keyboardDelegate = _machine;

    // Ensure that the view is the same size as the parent window before presenting the scene. Not
    // doing this causes the view to appear breifly at the size it is defined in the story board.
    self.skView.frame = self.skView.window.frame;
    
    // Present the scene
    [self.skView presentScene:_emulationScene];

    [self setupMachineBindings];
    [self setupSceneBindings];
    _firstUpdate = YES;
    
    [_machine start];
    
    [self setupGamepad];
    
}

- (void)setupSceneBindings
{
    [_emulationScene bind:@"displayCurve" toObject:_configViewController withKeyPath:@"displayCurve" options:nil];
    [_emulationScene bind:@"displaySaturation" toObject:_configViewController withKeyPath:@"displaySaturation" options:nil];
    [_emulationScene bind:@"displayContrast" toObject:_configViewController withKeyPath:@"displayContrast" options:nil];
    [_emulationScene bind:@"displayBrightness" toObject:_configViewController withKeyPath:@"displayBrightness" options:nil];
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

#pragma mark - View events

- (void)viewDidLayout
{
    [_emulationScene sceneViewSizeChanged:self.view.frame.size];
}

#pragma mark - Keyboard events

- (void)flagsChanged:(NSEvent *)event
{
    [_machine flagsChanged:event];
}

- (void)updateEmulationDisplayTextureWithImage:(SKTexture *)emulationDisplayTexture
{
    _emulationScene.emulationDisplaySprite.texture = emulationDisplayTexture;
    if (_firstUpdate)
    {
        _emulationScene.emulationDisplaySprite.hidden = NO;
        _firstUpdate = NO;
    }
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
    hidManager = IOHIDManagerCreate( kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    NSMutableDictionary* criterion = [[NSMutableDictionary alloc] init];
    [criterion setObject: [NSNumber numberWithInt: kHIDPage_GenericDesktop] forKey: (NSString*)CFSTR(kIOHIDDeviceUsagePageKey)];
    //    [criterion setObject: [NSNumber numberWithInt: kHIDUsage_GD_GamePad] forKey: (NSString*)CFSTR(kIOHIDDeviceUsageKey)];
    IOHIDManagerSetDeviceMatching(hidManager, (CFDictionaryRef)criterion);
    IOHIDManagerRegisterDeviceMatchingCallback(hidManager, gamepadWasAdded, (void*)self);
    IOHIDManagerRegisterDeviceRemovalCallback(hidManager, gamepadWasRemoved, (void*)self);
    IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    //    IOReturn tIOReturn = IOHIDManagerOpen(hidManager, kIOHIDOptionsTypeNone);
    IOHIDManagerRegisterInputValueCallback(hidManager, gamepadAction, (void*)self);
}

@end

