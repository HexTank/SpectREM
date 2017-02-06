//
//  ZXSpectrum48.m
//  ZXRetroEmu
//
//  Created by Mike Daley on 02/09/2016.
//  Copyright © 2016 71Squared Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ZXSpectrumSE.h"
#import "Z80Core.h"

#pragma mark - Extension Interface

@interface ZXSpectrumSE ()
{
    CZ80Core *core;
}

@end

#pragma mark - Implementation

@implementation ZXSpectrumSE

- (void)dealloc
{
    NSLog(@"Deallocating ZXSpectrum48");
    delete core;
    free (memory);
    free (rom);
    free(emuDisplayBuffer);
    free(self.audioBuffer);
}

- (instancetype)initWithEmulationViewController:(EmulationViewController *)emulationViewController machineInfo:(MachineInfo)info
{
    if (self = [super initWithEmulationViewController:emulationViewController machineInfo:info])
    {
        // We need 64k of memory total for the 48k Speccy
        memory = (unsigned char*)calloc(64 * 1024, sizeof(unsigned char));
        
        core = new CZ80Core;
        core->Initialise(coreMemoryRead,
                         coreMemoryWrite,
                         coreIORead,
                         coreIOWrite,
                         coreMemoryContention,
                         coreDebugRead,
                         (__bridge void *)self);
        
        displayPage = 1;
        disablePaging = YES;
        
        [self reset:YES];
        
    }
    return self;
}

- (void)start
{
    [super start];
    displayPage = 1;
}

- (void)reset:(BOOL)hard
{
    [super reset:hard];
    currentRAMPage = 0;
    currentROMPage = 0;
    displayPage = 1;
    disablePaging = YES;
}

#pragma mark - Memory Access

static unsigned char coreMemoryRead(unsigned short address, void *m)
{
    ZXSpectrumSE *machine = (__bridge ZXSpectrumSE *)m;
    return machine->memory[address];
}

static void coreMemoryWrite(unsigned short address, unsigned char data, void *m)
{
    ZXSpectrumSE *machine = (__bridge ZXSpectrumSE *)m;
    
    if (address < 16384)
    {
        return;
    }
    updateScreenWithTStates((machine->core->GetTStates() - machine->emuDisplayTs) + machine->machineInfo.paperDrawingOffset, m);
    machine->memory[address] = data;
}

static void coreMemoryContention(unsigned short address, unsigned int tstates, void *m)
{
    ZXSpectrumSE *machine = (__bridge ZXSpectrumSE *)m;
    
    if (address >= 16384 && address <= 32767)
    {
        machine->core->AddContentionTStates( machine->memoryContentionTable[machine->core->GetTStates() % machine->machineInfo.tsPerFrame] );
    }
}

static unsigned char coreDebugRead(unsigned short address, void *m)
{
	ZXSpectrumSE *machine = (__bridge ZXSpectrumSE *)m;
	return machine->memory[address];
}

#pragma mark - Load ROM

- (void)loadDefaultROM
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Open_SEBASIC_3.12" ofType:@"rom"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    
    const char *fileBytes = (const char*)[data bytes];
    
    for (int addr = 0; addr < data.length; addr++)
    {
        memory[addr] = fileBytes[addr];
    }
}

- (void *)getCore
{
    return (void*)core;
}

- (NSString *)machineName
{
    return @"ZX Spectrum 48k SE";
}

@end
