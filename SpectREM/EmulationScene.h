//
//  GameScene.h
//  SpectREM
//
//  Created by Mike Daley on 14/10/2016.
//  Copyright © 2016 71Squared Ltd. All rights reserved.
//

#import <SpriteKit/SpriteKit.h>

@interface EmulationScene : SKScene

#pragma mark - Properties

@property (strong) SKSpriteNode *emulationDisplaySprite;
@property (assign) id keyboardDelegate;

#pragma mark - Methods

// Called when the size of the scene view changes. Any updates that are needed when the size
// changes such as updating uniform values
- (void)sceneViewSizeChanged:(CGSize)newSize;

@end
