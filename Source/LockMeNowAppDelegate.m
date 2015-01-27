//
//  LockMeNowAppDelegate.m
//  Lock Me Now
//
//  Created by Vitaly Parovishnik on 20.07.11.
//  Copyright 2010 IGR Software. All rights reserved.
//

#import "LockMeNowAppDelegate.h"

#import "LockManager.h"
#import "JustLock.h"
#import "LoginWindowsLock.h"

#import "ListenerManager.h"
#import "KeyListener.h"
#import "USBListener.h"
#import "BluetoothListener.h"

#import "iTunesHelper.h"
#import "NSApplication+MXUtilities.h"

#import <Quartz/Quartz.h>

#import <xpc/xpc.h>

@interface LockMeNowAppDelegate() <LockManagerDelegate, ListenerManagerDelegate>

@property (nonatomic) xpc_connection_t scriptServiceConnection;
@property (nonatomic) IGRUserDefaults *userSettings;

@property (nonatomic) LockManager *lockManager;
@property (nonatomic) USBListener *usbListener;
@property (nonatomic) BluetoothListener *bluetoothListener;

@end

@implementation LockMeNowAppDelegate

- (instancetype) init
{
    if (self= [super init])
    {
        self.userSettings = [[IGRUserDefaults alloc] init];
    }
    
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)theNotification
{
    // Prep XPC services.
    [self registeryXPC];
    
    //Registery Listeners
    self.keyListener.userSettings = self.userSettings;
    self.keyListener.delegate = self;
    
    self.usbListener = [[USBListener alloc] initWithSettings:self.userSettings];
    self.usbListener.delegate = self;
    
    self.bluetoothListener = [[BluetoothListener alloc] initWithSettings:self.userSettings];
    self.bluetoothListener.delegate = self;
    
    __weak typeof(self) weakSelf = self;
    self.bluetoothListener.bluetoothStatusChangedBlock = ^(BluetoothStatus bluetoothStatus) {
        
        [weakSelf updateBluetoothStatus:bluetoothStatus];
    };
    
    //GUI
    [self.bluetoothStatus setBackgroundColor:[NSColor clearColor]];
    [self updateBluetoothStatus:OutOfRange];
    
    if (self.userSettings.bUseIconOnMainMenu)
    {
        [self makeMenu];
    }
    
    //Setup lock Type
    [self setupLock];
}

- (void)setupLock
{
    Class lockClass = NULL;
    switch ([self.userSettings lockingType])
    {
        case LOCK_SCREEN:
            lockClass = [JustLock class];
            break;
        case LOCK_BLOCK:
            //[self makeBlockLock];
            break;
        case LOCK_LOGIN_WINDOW:
        default:
            lockClass = [LoginWindowsLock class];
            break;
    }
    
    self.lockManager = [[lockClass alloc] initWithConnection:self.scriptServiceConnection settings:self.userSettings];
    self.lockManager.delegate = self;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
}

BOOL doNothingAtStart = NO;

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    if (doNothingAtStart)
    {
        doNothingAtStart = NO;
    }
    else
    {
        [self.window makeKeyAndOrderFront:self];
        [self.window center];
    }
}

- (void)applicationWillTerminate:(NSNotification *)theNotification
{
    [self.keyListener stopListen];
    [self.usbListener stopListen];
    [self.bluetoothListener stopListen];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    if (_lockManager.allowTerminate)
    {
        return NSTerminateNow;
    }
    
    return NSTerminateCancel;
}

#pragma mark - Actions

- (IBAction)goToURL:(id)sender
{
    NSURL *url = [NSURL URLWithString:@"http://igrsoft.com"];
    
    if ([[sender title] isEqualToString:@"Site"])
        url = [NSURL URLWithString:@"http://igrsoft.com" ];
    else if ([[sender title] isEqualToString:@"Twitter"])
        url = [NSURL URLWithString:@"http://twitter.com/#!/iKorich" ];
    else if ([sender tag] == 1)
        url = [NSURL URLWithString:@"http://russianapple.ru" ];
    
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)openPrefs:(id)sender
{
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront: self];
    [self.window makeMainWindow];
    [self.window center];
}

#pragma mark - Lock

- (IBAction)doLock:(id)sender
{
    self.userSettings.bNeedResumeiTunes = NO;
    [self pauseResumeMusic];
    
    [self.lockManager lock];
}

- (IBAction)doUnLock:(id)sender
{
    //[self removeSecurityLock];
}

#pragma mark - Preferences

- (IBAction)setMenuIcon:(id)sender
{
    [self makeMenu];
    
    [self updateUserSettings:sender];
}

- (IBAction)setMonitoringBluetooth:(id)sender
{
    if (self.userSettings.bMonitoringBluetooth)
    {
        [self.bluetoothListener startListen];
    }
    else
    {
        [self.bluetoothListener stopListen];
    }
    
    [self updateUserSettings:sender];
}

- (IBAction)setMonitoringUSBDevice:(id)sender
{
    if (self.userSettings.bMonitoringUSB)
    {
        [self.usbListener startListen];
    }
    else
    {
        [self.usbListener stopListen];
    }
    
    [self updateUserSettings:sender];
}

- (IBAction)toggleStartup:(id)sender
{
    [NSApplication sharedApplication].launchAtLogin = self.userSettings.bEnableStartup;
    
    [self updateUserSettings:sender];
}

- (IBAction)setLockType:(id)sender
{
    [self setupLock];
    
    [self updateUserSettings:sender];
}

- (IBAction)updateUserSettings:(id)sender
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [weakSelf.userSettings saveUserSettingsWithBluetoothData:nil];
    });
}

#pragma mark - Actions

- (void)pauseResumeMusic
{
    if (self.userSettings.bPauseiTunes)
    {
        if (!self.userSettings.bNeedResumeiTunes)
        {
            if ([iTunesHelper isItunesRuning] && [iTunesHelper isMusicPlaing])
            {
                [iTunesHelper playpause];
                self.userSettings.bNeedResumeiTunes = YES;
            }
        }
        else if (self.userSettings.bNeedResumeiTunes && self.userSettings.bResumeiTunes)
        {
            if ([iTunesHelper isItunesRuning] && [iTunesHelper isMusicPaused])
            {
                [iTunesHelper playpause];
                self.userSettings.bNeedResumeiTunes = NO;
            }
        }
    }
}

#pragma mark - Bluetooth

- (IBAction)changeDevice:(id)sender
{
    [self.bluetoothListener changeDevice];
}

#pragma mark - GUI

- (void)updateBluetoothStatus:(BluetoothStatus)bluetoothStatus
{
    NSString* path = [[NSBundle mainBundle] pathForResource: @"off"
                                                     ofType: @"pdf"];
    if(bluetoothStatus == InRange)
    {
        path = [[NSBundle mainBundle] pathForResource: @"on"
                                               ofType: @"pdf"];
    }
    
    NSURL* url = [NSURL fileURLWithPath: path];
    
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [weakSelf.bluetoothStatus setImageWithURL:url];
    });
}

- (void) makeMenu
{
    if (self.userSettings.bUseIconOnMainMenu && self.statusItem == nil)
    {
        NSStatusItem *statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
        
        NSStatusBarButton *button = statusItem.button;
        
        button.target = self;
        button.action = @selector(toggleDropDownMenu:);
        [button sendActionOn:NSLeftMouseUpMask|NSRightMouseUpMask];
        
        self.statusItem = statusItem;
        
        button.image = [NSImage imageNamed:@"lock"];
        button.appearsDisabled = NO;
        button.toolTip = NSLocalizedString(@"Click to show menu", nil);
        
    }
    else if (!self.userSettings.bUseIconOnMainMenu && self.statusItem != nil)
    {
        [[NSStatusBar systemStatusBar] removeStatusItem:self.statusItem];
        self.statusItem = nil;
    }
}

- (void)toggleDropDownMenu:(id)sender
{
    [self.statusItem popUpStatusItemMenu:self.statusMenu];
}

#pragma mark - XPC

- (void)registeryXPC
{
    self.scriptServiceConnection = [self connectionForServiceNamed:"com.igrsoft.lockmenow.script-service"
                                          connectionInvalidHandler:^{
                                              self.scriptServiceConnection = NULL;
                                          }];
    
    assert(self.scriptServiceConnection != NULL);
    
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    assert(message != NULL);
    
    xpc_dictionary_set_uint64(message, "encription", 1);
    
    __weak typeof(self) weakSelf = self;
    
    xpc_connection_send_message_with_reply(self.scriptServiceConnection, message,
                                           dispatch_get_main_queue(), ^(xpc_object_t event) {
                                               
                                               if (xpc_dictionary_get_value(event, "encription") != NULL)
                                               {
                                                   BOOL encription = xpc_dictionary_get_bool(event, "encription");
                                                   weakSelf.userSettings.bEncription = encription;
                                                   if (weakSelf.userSettings.bEncription)
                                                   {
                                                       weakSelf.userSettings.bAutoPrefs = NO;
                                                   }
                                                   
                                                   DBNSLog(@"Encription: %d", encription);
                                               }
                                           });
}

- (xpc_connection_t)connectionForServiceNamed:(const char *)serviceName
                     connectionInvalidHandler:(dispatch_block_t)handler
{
    __block xpc_connection_t serviceConnection =
    xpc_connection_create(serviceName, dispatch_get_main_queue());
    
    if (!serviceConnection)
    {
        NSLog(@"Can't connect to XPC service");
        return (NULL);
    }
    
    NSLog(@"Created connection to XPC service");
    
    xpc_connection_set_event_handler(serviceConnection, ^(xpc_object_t event) {
        
        xpc_type_t type = xpc_get_type(event);
        
        if (type == XPC_TYPE_ERROR)
        {
            if (event == XPC_ERROR_CONNECTION_INTERRUPTED)
            {
                // The service has either cancaled itself, crashed, or been
                // terminated.  The XPC connection is still valid and sending a
                // message to it will re-launch the service.  If the service is
                // state-full, this is the time to initialize the new service.
                
                NSLog(@"Interrupted connection to XPC service");
            }
            else if (event == XPC_ERROR_CONNECTION_INVALID)
            {
                // The service is invalid. Either the service name supplied to
                // xpc_connection_create() is incorrect or we (this process) have
                // canceled the service; we can do any cleanup of appliation
                // state at this point.
                NSLog(@"Connection Invalid error for XPC service");
                if (handler)
                {
                    handler();
                }
            }
            else
            {
                NSLog(@"Unexpected error for XPC service");
            }
        }
        else
        {
            NSLog(@"Received unexpected event for XPC service");
        }
    });
    
    // Need to resume the service in order for it to process messages.
    xpc_connection_resume(serviceConnection);
    return (serviceConnection);
}

#pragma mark - LockManagerDelegate

- (void)unLockSuccess
{
    [self pauseResumeMusic];
}

#pragma mark - ListenerManagerDelegate

- (void)makeAction:(id)sender
{
    [self doLock:sender];
}

@end
