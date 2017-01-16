//
//  ZXSpectrum.m
//  SpectREM
//
//  Created by Mike Daley on 26/10/2016.
//  Copyright © 2016 71Squared Ltd. All rights reserved.
//

#import "ZXSpectrum.h"
#import "KeyboardMatrix.h"
#import "Snapshot.h"
#import "Z80Core.h"

@interface ZXSpectrum ()


@end

@implementation ZXSpectrum

- (void)dealloc
{
    NSLog(@"Deallocating ZXSpectrum");
}

- (instancetype)initWithEmulationViewController:(EmulationViewController *)emulationViewController machineInfo:(MachineInfo)info
{
    if (self = [super init])
    {        
        machineInfo = info;
        _emulationViewController = emulationViewController;
        
        event = EventType::eNone;
        
        borderColor = 7;
        frameCounter = 0;
        
        emuLeftBorderPx = 32;
        emuRightBorderPx = 32;
        
        emuBottomBorderPx = 32;
        emuTopBorderPx = 32;
        
        emuDisplayPxWidth = 256 + emuLeftBorderPx + emuRightBorderPx;
        emuDisplayPxHeight = 192 + emuTopBorderPx + emuBottomBorderPx;
        
        emuHScale = 1.0 / emuDisplayPxWidth;
        emuVScale = 1.0 / emuDisplayPxHeight;
        
        emuDisplayTs = 0;

        // Setup the display buffer and length used to store the output from the emulator
        emuDisplayBufferLength = (emuDisplayPxWidth * emuDisplayPxHeight) * sizeof(PixelData);
        emuDisplayBuffer = (unsigned char *)calloc(emuDisplayBufferLength, sizeof(unsigned char));

        self.emulationQueue = dispatch_queue_create("emulationQueue", nil);

        float fps = 50;
        
        audioBufferSize = (cAudioSampleRate / fps) * 6;
        audioTsStep = machineInfo.tsPerFrame / (cAudioSampleRate / fps);
        audioAYTStatesStep = 32;
        self.audioBuffer = (int16_t *)malloc(audioBufferSize);
        
        [self resetFrame];
        [self resetSound];
        [self buildContentionTable];
        [self buildScreenLineAddressTable];
        [self buildDisplayTsTable];
        [self resetKeyboardMap];
    
        self.audioCore = [[AudioCore alloc] initWithSampleRate:cAudioSampleRate
                                               framesPerSecond:50
                                                emulationQueue:self.emulationQueue
                                                       machine:self];
        [self.audioCore reset];
        [self setupObservers];
    
    }
    return self;
}

#pragma mark - Binding

- (void)setupObservers
{
    [self addObserver:self.audioCore forKeyPath:@"soundLowPassFilter" options:NSKeyValueObservingOptionNew context:NULL];
    [self addObserver:self.audioCore forKeyPath:@"soundHighPassFilter" options:NSKeyValueObservingOptionNew context:NULL];
    [self addObserver:self.audioCore forKeyPath:@"soundVolume" options:NSKeyValueObservingOptionNew context:NULL];
}

- (void)removeObservers
{
    [self removeObserver:self.audioCore forKeyPath:@"soundLowPassFilter"];
    [self removeObserver:self.audioCore forKeyPath:@"soundHighPassFilter"];
    [self removeObserver:self.audioCore forKeyPath:@"soundVolume"];
}

#pragma mark - Emulation Control

- (void)start
{
    [self.audioCore start];
    [self resetFrame];
    [self doFrame];
}

- (void)stop
{
    [self removeObservers];
    [self.audioCore stop];
}

#pragma mark - Reset

- (void)reset:(BOOL)hard
{
    frameCounter = 0;
    [self resetKeyboardMap];
    [self resetSound];
    [self resetFrame];
    CZ80Core *core = (CZ80Core *)[self getCore];
    core->Reset(hard);
    
    if (hard)
    {
        [self loadDefaultROM];
    }
}

- (void)resetSound
{
    memset(self.audioBuffer, 0, audioBufferSize);
    audioBufferIndex = 0;
    audioTsCounter = 0;
    audioTsStepCounter = 0;
    audioBeeperLeft = 0;
    audioBeeperRight = 0;
    [self.audioCore reset];
}

- (void)resetFrame
{
    // Reset display
    emuDisplayBufferIndex = 0;
    emuDisplayTs = 0;
    
    // Reset audio
    audioBufferIndex = 0;
    audioTsCounter = 0;
    audioTsStepCounter = 0;
}

#pragma mark - CPU

- (void)doFrame
{
    // Ensure that the frame is run on the emulation queue
    dispatch_async(self.emulationQueue, ^
                   {
                       switch (event)
                       {
                           case EventType::eNone:
                               break;
                               
                           case EventType::eReset:
                               break;
                               
                           case EventType::eSnapshot:
                               [self loadSnapshot];
                               break;
                               
                           case EventType::eZ80Snapshot:
                               [self loadZ80Snapshot];
                               break;
                               
                           default:
                               break;
                       }
                       event = EventType::eNone;
                       [self resetFrame];
                       [self generateFrame];
                   });
}

- (void)generateFrame
{
    CZ80Core *core = (CZ80Core *)[self getCore];

    int count = machineInfo.tsPerFrame;
    
    while (count > 0)
    {
        int tsCPU = core->Execute(1, machineInfo.intLength);
        
        if (self.zxTape.playing)
        {
            [self.zxTape updateTapeWithTStates:tsCPU];
        }
        
        count -= tsCPU;
        
        updateAudioWithTStates(tsCPU, (__bridge void *)self, machineInfo.hasAY);
        
        if (core->GetTStates() >= machineInfo.tsPerFrame )
        {
            // Must reset count to ensure we leave the while loop at the correct point
            count = 0;
            
            updateScreenWithTStates(machineInfo.tsPerFrame - emuDisplayTs, (__bridge void *)self);
            
            core->ResetTStates( machineInfo.tsPerFrame );
            core->SignalInterrupt();
            
            // Use the configurable border width to work out the rect that should be extraced from the texture
            CGRect textureRect = (CGRect){0, 0, 1, 1};
            if (self.displayBorderWidth != emuTopBorderPx)
            {
                float borderWidth = emuTopBorderPx - self.displayBorderWidth;
                textureRect = (CGRect){
                    borderWidth * emuHScale,
                    borderWidth * emuVScale,
                    1.0 - (borderWidth * 2.0 * emuHScale),
                    1.0 - (borderWidth * 2.0 * emuVScale)
                };
            }
            
            // Update the display texture using the data from the emulator display buffer
            CFDataRef dataRef = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, emuDisplayBuffer, emuDisplayBufferLength, kCFAllocatorNull);
            self.texture = [SKTexture textureWithData:(__bridge NSData *)dataRef
                                                 size:CGSizeMake(emuDisplayPxWidth, emuDisplayPxHeight)
                                              flipped:YES];
            
            self.texture = [SKTexture textureWithRect:textureRect inTexture:self.texture];
            
            CFRelease(dataRef);
            
            // Updating the emulators texture must be done on the main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.emulationViewController updateEmulationDisplayWithTexture:self.texture];
            });
            
            frameCounter++;
        }
    }
}

#pragma mark - Load IF2 ROM

- (void)loadROMWithPath:(NSString *)path
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    
    const char *fileBytes = (const char*)[data bytes];
    
    for (int addr = 0; addr < data.length; addr++)
    {
        memory[addr] = fileBytes[addr];
    }
}

#pragma mark - Audio

- (void)loadDefaultROM
{
    // Implemented in subclasses
}

#pragma mark - Audio

void updateAudioWithTStates(int numberTs, void *m, bool hasAY)
{
    ZXSpectrum *machine = (__bridge ZXSpectrum *)m;
    
    // Loop over each tState so that the necessary audio samples can be generated
    for(int i = 0; i < numberTs; i++)
    {
        // Grab the current state of the audio ear output & the tapeLevel which is used to register input when loading tapes
        signed int beeperLevelLeft = ((machine->audioEarBit | machine->_zxTape->tapeInputBit) * cAudioBeeperVolumeMultiplier);
        signed int beeperLevelRight = beeperLevelLeft;
        
        // Setting the channel mix 0.5 causes the output to to be centered between left and right speakers
        double leftMix = 0.5;
        double rightMix = 0.5;
        
        if (hasAY)
        {
            machine->audioAYTStates++;
            if (machine->audioAYTStates >= machine->audioAYTStatesStep)
            {
                [machine.audioCore updateAY:1];
                
                if (machine.AYChannelA)
                {
                    if (machine.AYChannelABalance > 0.5)
                    {
                        leftMix = 1.0 - machine.AYChannelABalance;
                        rightMix = machine.AYChannelABalance;
                    }
                    else if (machine.AYChannelABalance < 0.5)
                    {
                        leftMix = 1.0 - (machine.AYChannelABalance * 2);
                        rightMix = 1.0 - (1.0 - machine.AYChannelABalance);
                    }
                    signed int channelA = machine.audioCore.getChannelA;
                    beeperLevelLeft += (channelA * leftMix);
                    beeperLevelRight += (channelA * rightMix);
                }
                if (machine.AYChannelB)
                {
                    leftMix = 0.5;
                    rightMix = 0.5;
                    if (machine.AYChannelBBalance > 0.5)
                    {
                        leftMix = 1.0 - machine.AYChannelBBalance;
                        rightMix = machine.AYChannelBBalance;
                    }
                    else if (machine.AYChannelBBalance < 0.5)
                    {
                        leftMix = 1.0 - (machine.AYChannelBBalance * 2);
                        rightMix = 1.0 - (1.0 - machine.AYChannelBBalance);
                    }
                    signed int channelB = machine.audioCore.getChannelB;
                    beeperLevelLeft += (channelB * leftMix);
                    beeperLevelRight += (channelB * rightMix);
                }
                if (machine.AYChannelC)
                {
                    leftMix = 0.5;
                    rightMix = 0.5;
                    if (machine.AYChannelCBalance > 0.5)
                    {
                        leftMix = 1.0 - machine.AYChannelCBalance;
                        rightMix = machine.AYChannelCBalance;
                    }
                    else if (machine.AYChannelCBalance < 0.5)
                    {
                        leftMix = 1.0 - (machine.AYChannelCBalance * 2);
                        rightMix = 1.0 - (1.0 - machine.AYChannelCBalance);
                    }
                    signed int channelC = machine.audioCore.getChannelC;
                    beeperLevelLeft += (channelC * leftMix);
                    beeperLevelRight += (channelC * rightMix);
                }
                
                [machine.audioCore endFrame];
                machine->audioAYTStates -= machine->audioAYTStatesStep;
            }
        }
        
        // If we have done more cycles now than the audio step counter, generate a new sample
        if (machine->audioTsCounter++ >= machine->audioTsStepCounter)
        {
            // Quantize the value loaded into the audio buffer e.g. if cycles = 19 and step size is 18.2
            // 0.2 of the beeper value goes into this sample and 0.8 goes into the next sample
            double delta1 = fabs(machine->audioTsStepCounter - (machine->audioTsCounter - 1));
            double delta2 = (1 - delta1);
            
            // Quantize for the current sample
            machine->audioBeeperLeft += beeperLevelLeft * delta1;
            machine->audioBeeperRight += beeperLevelRight * delta1;
            
            // Load the buffer with the sample for both left and right channels
            machine.audioBuffer[ machine->audioBufferIndex++ ] = (signed short)machine->audioBeeperLeft;
            machine.audioBuffer[ machine->audioBufferIndex++ ] = (signed short)machine->audioBeeperRight;
            
            // Quantize for the next sample
            machine->audioBeeperLeft = beeperLevelLeft * delta2;
            machine->audioBeeperRight = beeperLevelRight * delta2;
            
            // Increment the step counter so that the next sample will be taken after another 18.2 T-States
            machine->audioTsStepCounter += machine->audioTsStep;
        }
        else
        {
            machine->audioBeeperLeft += beeperLevelLeft;
            machine->audioBeeperRight += beeperLevelRight;
        }
    }
}

#pragma mark - Display

void updateScreenWithTStates(int numberTs, void *m)
{
    ZXSpectrum *machine = (__bridge ZXSpectrum *)m;
    
    while (numberTs > 0)
    {
        int line = machine->emuDisplayTs / machine->machineInfo.tsPerLine;
        int ts = machine->emuDisplayTs % machine->machineInfo.tsPerLine;
        
        switch (machine->emuDisplayTsTable[line][ts])
        {
            case DisplayAction::eDisplayRetrace:
                break;
                
            case DisplayAction::eDisplayBorder:
                for (int i = 0; i < 8; i++)
                {
                    machine->emuDisplayBuffer[machine->emuDisplayBufferIndex++] = pallette[machine->borderColor].r;
                    machine->emuDisplayBuffer[machine->emuDisplayBufferIndex++] = pallette[machine->borderColor].g;
                    machine->emuDisplayBuffer[machine->emuDisplayBufferIndex++] = pallette[machine->borderColor].b;
                    machine->emuDisplayBuffer[machine->emuDisplayBufferIndex++] = pallette[machine->borderColor].a;                    
                }
                break;
                
            case DisplayAction::eDisplayPaper:
            {
                int y = line - (machine->machineInfo.pxVerticalBlank + machine->machineInfo.pxTopBorder);
                int x = (ts >> 2) - 4;
                
                uint pixelAddress = machine->emuTsLine[y] + x;
                uint attributeAddress = cBitmapSize + ((y >> 3) << 5) + x;
                
                int pixelByte = machine->memory[(machine->displayPage * 16384) + pixelAddress];
                int attributeByte = machine->memory[(machine->displayPage * 16384) + attributeAddress];
                
                // Extract the ink and paper colours from the attribute byte read in
                int ink = (attributeByte & 0x07) + ((attributeByte & 0x40) >> 3);
                int paper = ((attributeByte >> 3) & 0x07) + ((attributeByte & 0x40) >> 3);
                
                // Switch ink and paper if the flash phase has changed
                if ((machine->frameCounter & 16) && (attributeByte & 0x80))
                {
                    int tempPaper = paper;
                    paper = ink;
                    ink = tempPaper;
                }
                
                for (int b = 0x80; b; b >>= 1)
                {
                    if (pixelByte & b) {
                        machine->emuDisplayBuffer[machine->emuDisplayBufferIndex++] = pallette[ink].r;
                        machine->emuDisplayBuffer[machine->emuDisplayBufferIndex++] = pallette[ink].g;
                        machine->emuDisplayBuffer[machine->emuDisplayBufferIndex++] = pallette[ink].b;
                        machine->emuDisplayBuffer[machine->emuDisplayBufferIndex++] = pallette[ink].a;
                    }
                    else
                    {
                        machine->emuDisplayBuffer[machine->emuDisplayBufferIndex++] = pallette[paper].r;
                        machine->emuDisplayBuffer[machine->emuDisplayBufferIndex++] = pallette[paper].g;
                        machine->emuDisplayBuffer[machine->emuDisplayBufferIndex++] = pallette[paper].b;
                        machine->emuDisplayBuffer[machine->emuDisplayBufferIndex++] = pallette[paper].a;
                    }
                }
                break;
            }
                
            default:
                break;
        }
        
        machine->emuDisplayTs += machine->machineInfo.tsPerChar;
        numberTs -= machine->machineInfo.tsPerChar;
    }
}

#pragma mark - IO Access

// Calculate the necessary contention based on the Port number being accessed and if the port belongs to the ULA.
// All non-even port numbers below to the ULA. N:x means no contention to be added and just advance the tStates.
// C:x means that contention should be calculated based on the current tState value and then x tStates are to be
// added to the current tState count
//
// in 40 - 7F?| Low bit | Contention pattern
//------------+---------+-------------------
//		No    |  Reset  | N:1, C:3
//		No    |   Set   | N:4
//		Yes   |  Reset  | C:1, C:3
//		Yes   |   Set   | C:1, C:1, C:1, C:1
//
unsigned char coreIORead(unsigned short address, void *m)
{
    ZXSpectrum *machine = (__bridge ZXSpectrum *)m;
    CZ80Core *core = (CZ80Core *)[machine getCore];
    
    bool contended = false;
    int page = address / 16384;
    
    // Identify contention on the 48k
    if (!machine->machineInfo.hasPaging && page == 1)
    {
        contended = true;
    }
    
    // Identify contention on the 128k
    if (machine->machineInfo.hasPaging &&
        (page == 1 ||
         (page == 3 && (machine->currentRAMPage == 1 || machine->currentRAMPage == 3 || machine->currentRAMPage == 5 || machine->currentRAMPage == 7))))
    {
        contended = true;
    }
    
    // Apply contention
    if (contended)
    {
        if ((address & 1) == 0)
        {
            core->AddContentionTStates( machine->memoryContentionTable[core->GetTStates() % machine->machineInfo.tsPerFrame] );
            core->AddTStates(1);
            core->AddContentionTStates( machine->memoryContentionTable[core->GetTStates() % machine->machineInfo.tsPerFrame] );
            core->AddTStates(3);
        }
        else
        {
            core->AddContentionTStates( machine->memoryContentionTable[core->GetTStates() % machine->machineInfo.tsPerFrame] );
            core->AddTStates(1);
            core->AddContentionTStates( machine->memoryContentionTable[core->GetTStates() % machine->machineInfo.tsPerFrame] );
            core->AddTStates(1);
            core->AddContentionTStates( machine->memoryContentionTable[core->GetTStates() % machine->machineInfo.tsPerFrame] );
            core->AddTStates(1);
            core->AddContentionTStates( machine->memoryContentionTable[core->GetTStates() % machine->machineInfo.tsPerFrame] );
            core->AddTStates(1);
        }
    } else {
        if ((address & 1) == 0)
        {
            core->AddTStates(1);
            core->AddContentionTStates( machine->memoryContentionTable[core->GetTStates() % machine->machineInfo.tsPerFrame] );
            core->AddTStates(3);
        }
        else
        {
            core->AddTStates(4);
        }
    }
    
    // If the address is odd and does not belong to the ULA then return the floating bus value
    if (address & 0x01)
    {
        // TODO: Add Kemptston joystick support. Until then return 0. Byte returned by a Kempston joystick is in the
        // format: 000FDULR. F = Fire, D = Down, U = Up, L = Left, R = Right
        // Joystick is read first as it takes priority if you read from a port that activates the keyboard as well on a
        // real machine.
        if ((address & 0xff) == 0x1f)
        {
            return 0x0;
        }
        else if ((address & 0xc002) == 0xc000)
        {
            return [machine.audioCore readAYData];
        }
        
        return floatingBus(m);
    }
    
    // Default return value
    int result = 0xff;
    
    // Check to see if any keys have been pressed
    for (int i = 0; i < 8; i++)
    {
        if (!(address & (0x100 << i)))
        {
            result &= machine->keyboardMap[i];
        }
    }

    // To emulate a series 3, the result of reading a ULA port should have bits 5+7 set and bit 6 should be set
    // to the last value of the bit 4 when writing to port 0xFE.
    result = (result & 191) | (machine->audioEarBit << 6) | (machine->_zxTape->tapeInputBit << 6);
    
    return result;
}

void coreIOWrite(unsigned short address, unsigned char data, void *m)
{
    ZXSpectrum *machine = (__bridge ZXSpectrum *)m;
    CZ80Core *core = (CZ80Core *)[machine getCore];
    
    bool contended = false;
    int page = address / 16384;
    
    // Identify contention in the 48k
    if (!machine->machineInfo.hasPaging && page == 1)
    {
        contended = true;
    }
    
    // Identify contention in the 128k
    if (machine->machineInfo.hasPaging &&
             (page == 1 ||
              (page == 3 && (machine->currentRAMPage == 1 || machine->currentRAMPage == 3 || machine->currentRAMPage == 5 || machine->currentRAMPage == 7))))
    {
        contended = true;
    }
    
    // Apply contention
    if (contended)
    {
        if ((address & 1) == 0)
        {
            core->AddContentionTStates( machine->memoryContentionTable[core->GetTStates() % machine->machineInfo.tsPerFrame] );
            core->AddTStates(1);
            core->AddContentionTStates( machine->memoryContentionTable[core->GetTStates() % machine->machineInfo.tsPerFrame] );
            core->AddTStates(3);
        }
        else
        {
            core->AddContentionTStates( machine->memoryContentionTable[core->GetTStates() % machine->machineInfo.tsPerFrame] );
            core->AddTStates(1);
            core->AddContentionTStates( machine->memoryContentionTable[core->GetTStates() % machine->machineInfo.tsPerFrame] );
            core->AddTStates(1);
            core->AddContentionTStates( machine->memoryContentionTable[core->GetTStates() % machine->machineInfo.tsPerFrame] );
            core->AddTStates(1);
            core->AddContentionTStates( machine->memoryContentionTable[core->GetTStates() % machine->machineInfo.tsPerFrame] );
            core->AddTStates(1);
        }
    }
    else
    {
        if ((address & 1) == 0)
        {
            core->AddTStates(1);
            core->AddContentionTStates( machine->memoryContentionTable[core->GetTStates() % machine->machineInfo.tsPerFrame] );
            core->AddTStates(3);
        }
        else
        {
            core->AddTStates(4);
        }
    }
    
    // Port: 0xFE
    //   7   6   5   4   3   2   1   0
    // +---+---+---+---+---+-----------+
    // |   |   |   | E | M |  BORDER   |
    // +---+---+---+---+---+-----------+
    if (!(address & 0x01))
    {
        updateScreenWithTStates((core->GetTStates() - machine->emuDisplayTs) + machine->machineInfo.borderDrawingOffset, m);
        machine->audioEarBit = (data & 0x10) >> 4;
        machine->audioMicBit = (data & 0x08) >> 3;
        machine->borderColor = data & 0x07;
    }
    
    if ( (address & 0x8002) == 0 && machine->disablePaging == NO)
    {
        if (machine->displayPage != ((data & 0x08) == 0x08) ? 7 : 5)
        {
            updateScreenWithTStates((core->GetTStates() - machine->emuDisplayTs) + machine->machineInfo.borderDrawingOffset, m);
        }
        
        // This is the paging port
        machine->disablePaging = ((data & 0x20) == 0x20) ? YES : NO;
        machine->currentROMPage = ((data & 0x10) == 0x10) ? 1 : 0;
        machine->displayPage = ((data & 0x08) == 0x08) ? 7 : 5;
        machine->currentRAMPage = (data & 0x07);
    }
    
    if((address & 0xc002) == 0xc000 && machine->machineInfo.hasAY)
    {
        [machine.audioCore setAYRegister:(data & 0x0f)];
    }
    
    if ((address & 0xc002) == 0x8000 && machine->machineInfo.hasAY)
    {
        [machine.audioCore writeAYData:data];
    }
}

#pragma mark - Build Display Tables

// Stores the memory address for the start of each bitmap line on the screen
- (void)buildScreenLineAddressTable
{
    for(int i = 0; i < 3; i++)
    {
        for(int j = 0; j < 8; j++)
        {
            for(int k = 0; k < 8; k++)
            {
                emuTsLine[(i << 6) + (j << 3) + k] = (i << 11) + (j << 5) + (k << 8);
            }
        }
    }
}

// Generates a table that holds what screen activity should be happening based on each T-States within a Frame e.g. should the
// border be drawn, bitmap screen or beam retrace. The values have been adjusted to ensure that the image drawn will be 320x256.
- (void)buildDisplayTsTable
{
    
    for(int line = 0; line < machineInfo.pxVerticalTotal; line++)
    {
        for(int ts = 0 ; ts < machineInfo.tsPerLine; ts++)
        {
            if (line >= 0  && line < machineInfo.pxVerticalBlank)
            {
                emuDisplayTsTable[line][ts] = DisplayAction::eDisplayRetrace;
            }
            
            // Top Border
            if (line >= machineInfo.pxVerticalBlank && line < machineInfo.pxVerticalBlank + machineInfo.pxTopBorder)
            {
                if ((ts >= 160 && ts < machineInfo.tsPerLine) || line < machineInfo.pxVerticalBlank + machineInfo.pxTopBorder - emuTopBorderPx)
                {
                    emuDisplayTsTable[line][ts] = DisplayAction::eDisplayRetrace;
                }
                else
                {
                    emuDisplayTsTable[line][ts] = DisplayAction::eDisplayBorder;
                }
            }

            // Border + Paper + Border
            if (line >= (machineInfo.pxVerticalBlank + machineInfo.pxTopBorder) && line < (machineInfo.pxVerticalBlank + machineInfo.pxTopBorder + machineInfo.pxVerticalDisplay))
            {
                if ((ts >= 0 && ts < 16) || (ts >= 144 && ts < 160))
                {
                    emuDisplayTsTable[line][ts] = DisplayAction::eDisplayBorder;
                }
                else if (ts >= 160 && ts < machineInfo.tsPerLine)
                {
                    emuDisplayTsTable[line][ts] = DisplayAction::eDisplayRetrace;
                }
                else
                {
                    emuDisplayTsTable[line][ts] = DisplayAction::eDisplayPaper;
                }
            }

            // Bottom Border
            if (line >= (machineInfo.pxVerticalBlank + machineInfo.pxTopBorder + machineInfo.pxVerticalDisplay) && line < machineInfo.pxVerticalTotal - 24)
            {
                if (ts >= 160 && ts < machineInfo.tsPerLine)
                {
                    emuDisplayTsTable[line][ts] = DisplayAction::eDisplayRetrace;
                }
                else
                {
                    emuDisplayTsTable[line][ts] = DisplayAction::eDisplayBorder;
                }
            }
            
        }
    }
}

#pragma mark - Floating Bus

// When the Z80 reads from an unattached port, such as 0xFF, it actually reads the data currently on the
// Spectrums ULA data bus. This may happen to be a byte being transferred from screen memory. If the ULA
// is building the border then the bus is idle and the return value is 0xFF, otherwise its possible to
// predict if the ULA is reading a pixel or attribute byte based on the current t-state.
// This routine works out what would be on the ULA bus for a given t-state and returns the result
static unsigned char floatingBus(void *m)
{
    ZXSpectrum *machine = (__bridge ZXSpectrum *)m;
    CZ80Core *core = (CZ80Core *)[machine getCore];

    int cpuTs = core->GetTStates() - 1;
    int currentDisplayLine = (cpuTs / machine->machineInfo.tsPerLine);
    int currentTs = (cpuTs % machine->machineInfo.tsPerLine);
    
    // If the line and tState are within the bitmap of the screen then grab the
    // pixel or attribute value
    if (currentDisplayLine >= (32 + machine->machineInfo.pxVerticalBlank)
        && currentDisplayLine < (32 + machine->machineInfo.pxVerticalBlank + machine->machineInfo.pxVerticalDisplay)
        && currentTs <= machine->machineInfo.tsHorizontalDisplay)
    {
        unsigned char ulaValueType = cFloatingBusTable[ currentTs & 0x07 ];
        
        int y = currentDisplayLine - (32 + machine->machineInfo.pxVerticalBlank);
        int x = currentTs >> 2;
        
        if (ulaValueType == FloatingBusValueType::ePixel)
        {
            return machine->memory[cBitmapAddress + machine->emuTsLine[y] + x];
        }
        
        if (ulaValueType == FloatingBusValueType::eAttribute)
        {
            return machine->memory[cBitmapAddress + cBitmapSize + ((y >> 3) << 5) + x];
        }
    }
    
    return 0xff;
}

#pragma mark - Contention Tables

- (void)buildContentionTable
{
    for (int i = 0; i < machineInfo.tsPerFrame; i++)
    {
        memoryContentionTable[i] = 0;
        ioContentionTable[i] = 0;
        
        if (i >= machineInfo.tsToOrigin)
        {
            uint32 line = (i - machineInfo.tsToOrigin) / machineInfo.tsPerLine;
            uint32 ts = (i - machineInfo.tsToOrigin) % machineInfo.tsPerLine;
            
            if (line < 192 && ts < 128)
            {
                memoryContentionTable[i] = cContentionValues[ ts & 0x07 ];
                ioContentionTable[i] = cContentionValues[ ts & 0x07 ];
            }
        }
    }
}

#pragma mark - View Event Protocol Methods

- (void)keyDown:(NSEvent *)theEvent
{
    if (!theEvent.isARepeat && !(theEvent.modifierFlags & NSEventModifierFlagCommand))
    {
        // Because keyboard updates are called on the main thread, changes to the keyboard map
        // must be done on the emulation queue to prevent a race condition
        dispatch_sync(self.emulationQueue, ^{
            switch (theEvent.keyCode)
            {
                case 51: // Backspace
                    keyboardMap[0] &= ~0x01; // Shift
                    keyboardMap[4] &= ~0x01; // 0
                    break;
                    
                case 126: // Arrow up
                    keyboardMap[0] &= ~0x01; // Shift
                    keyboardMap[4] &= ~0x08; // 7
                    break;
                    
                case 125: // Arrow down
                    keyboardMap[0] &= ~0x01; // Shift
                    keyboardMap[4] &= ~0x10; // 6
                    break;
                    
                case 123: // Arrow left
                    keyboardMap[0] &= ~0x01; // Shift
                    keyboardMap[3] &= ~0x10; // 5
                    break;
                    
                case 124: // Arrow right
                    keyboardMap[0] &= ~0x01; // Shift
                    keyboardMap[4] &= ~0x04; // 8
                    break;
                    
                default:
                    for (NSUInteger i = 0; i < sizeof(keyboardLookup) / sizeof(keyboardLookup[0]); i++)
                    {
                        if (keyboardLookup[i].keyCode == theEvent.keyCode)
                        {
                            keyboardMap[keyboardLookup[i].mapEntry] &= ~(1 << keyboardLookup[i].mapBit);
                            break;
                        }
                    }
                    break;
            }
        });
    }
}

- (void)keyUp:(NSEvent *)theEvent
{
    if (!theEvent.isARepeat && !(theEvent.modifierFlags & NSEventModifierFlagCommand))
    {
        // Because keyboard updates are called on the main thread, changes to the keyboard map
        // must be done on the emulation queue to prevent a race condition
        dispatch_sync(self.emulationQueue, ^{
            switch (theEvent.keyCode)
            {
                case 51: // Backspace
                    keyboardMap[0] |= 0x01; // Shift
                    keyboardMap[4] |= 0x01; // 0
                    break;
                    
                case 126: // Arrow up
                    keyboardMap[0] |= 0x01; // Shift
                    keyboardMap[4] |= 0x08; // 7
                    break;
                    
                case 125: // Arrow down
                    keyboardMap[0] |= 0x01; // Shift
                    keyboardMap[4] |= 0x10; // 6
                    break;
                    
                case 123: // Arrow left
                    keyboardMap[0] |= 0x01; // Shift
                    keyboardMap[3] |= 0x10; // 5
                    break;
                    
                case 124: // Arrow right
                    keyboardMap[0] |= 0x01; // Shift
                    keyboardMap[4] |= 0x04; // 8
                    break;
                    
                default:
                    for (NSUInteger i = 0; i < sizeof(keyboardLookup) / sizeof(keyboardLookup[0]); i++)
                    {
                        if (keyboardLookup[i].keyCode == theEvent.keyCode)
                        {
                            keyboardMap[keyboardLookup[i].mapEntry] |= (1 << keyboardLookup[i].mapBit);
                            break;
                        }
                    }
                    break;
            }
        });
    }
}

- (void)flagsChanged:(NSEvent *)theEvent
{
    if (!(theEvent.modifierFlags & NSEventModifierFlagCommand))
    {
        // Because keyboard updates are called on the main thread, changes to the keyboard map
        // must be done on the emulation queue to prevent a race condition
        dispatch_sync(self.emulationQueue, ^{
            switch (theEvent.keyCode)
            {
                case 58: // Alt Right - This puts the keyboard into extended mode in a single keypress
                case 61: // Alt Left
                    if (theEvent.modifierFlags & NSEventModifierFlagOption)
                    {
                        keyboardMap[0] &= ~0x01;
                        keyboardMap[7] &= ~0x02;
                    }
                    else
                    {
                        keyboardMap[0] |= 0x01;
                        keyboardMap[7] |= 0x02;
                    }
                    break;
                    
                case 56: // Left Shift
                case 60: // Right Shift
                    if (theEvent.modifierFlags & NSEventModifierFlagShift)
                    {
                        keyboardMap[0] &= ~0x01;
                    }
                    else
                    {
                        keyboardMap[0] |= 0x01;
                    }
                    break;
                    
                case 59: // Control
                    if (theEvent.modifierFlags & NSEventModifierFlagControl)
                    {
                        keyboardMap[7] &= ~0x02;
                    }
                    else
                    {
                        keyboardMap[7] |= 0x02;
                    }
                    
                default:
                    break;
            }
        });
    }
}

- (void)resetKeyboardMap
{
    for (int i = 0; i < 8; i++)
    {
        keyboardMap[i] = 0xff;
    }
}

#pragma mark - Snapshot Loading

- (void)loadSnapshotWithPath:(NSString *)path
{
    // This will be called from the main thread so it needs to by sync'd with the emulation queue
    dispatch_sync(self.emulationQueue, ^
      {
          self.snapshotPath = path;
          NSString *extension = [[path pathExtension] uppercaseString];
          
          if ([extension isEqualToString:@"SNA"])
          {
              event = EventType::eSnapshot;
          }
          
          if ([extension isEqualToString:@"Z80"])
          {
              event = EventType::eZ80Snapshot;
          }
      });
}

- (void)loadSnapshot
{
    [self reset:NO];
    int status = [Snapshot loadSnapshotWithPath:self.snapshotPath IntoMachine:self];
    [self verifySnapshotLoadWithStatus:status];
}

- (void)loadZ80Snapshot
{
    [self reset:NO];
    int status = [Snapshot loadZ80SnapshotWithPath:self.snapshotPath intoMachine:self];
    [self verifySnapshotLoadWithStatus:status];
}

- (void)verifySnapshotLoadWithStatus:(int)status
{
    switch (status) {
        case 0:
            [self resetSound];
            [self resetKeyboardMap];
            break;
            
        case 1:
            break;
        default:
            break;
    }
}

#pragma mark - Getters

// This is implemented within each machine class and returna a reference to the core being used for that machinne
- (void *)getCore;
{
    return nil;
}

// Returns the string name for a machine. Each machine class implements this method and returns the appropriate machine name
- (NSString *)machineName
{
    return @"Unknown";
}

@end
