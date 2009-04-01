//
//  MediaNox.h
//  MediaNox
//
//  Created by Björn Teichmann on 19.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface MediaNox : NSObject {

	IBOutlet NSObjectController *myLinker;
	
	IBOutlet NSWindow *window;
	
	
	IBOutlet NSTextView *statusText;
	IBOutlet NSScrollView *statusTextScrollview;
	IBOutlet NSArrayController *queueController;
	
	IBOutlet NSArrayController *ffmpegBinaries;
	
	IBOutlet NSProgressIndicator *monitorWheel;
	
	IBOutlet NSTableView *queueTable;
			
	IBOutlet NSLevelIndicator *ffmpegState;
	
	IBOutlet NSButton *stopButton;
	
	IBOutlet NSView *queueView;
	
	IBOutlet NSTextField *ffmpegBitrate;
	IBOutlet NSTextField *timeLeft;
	
	NSTask *ffmpegConvertTask;
	NSMutableDictionary *currentMediaFile;
	
	BOOL stoppedState;
	
	NSTimer *monitorFolderTimer;
	
	NSTimeInterval fiveSecondsAgoCheckDate;
	double fiveSecondsAgoCheckCTime;
	
	IBOutlet NSWindow *preferencesWindow;
	IBOutlet NSTabView *settingsTabs;
	IBOutlet NSPopUpButton *moveSourcePopupButton;
	IBOutlet NSPopUpButton *tempMonitoredFolderPopupButton;
}


- (void) saveQueue;
- (void) loadQueue;


- (void) stopAllConversionsTasks;
- (void) queueTheseFiles: (NSArray *) _filesToQueue inDirectory: (NSString *) _dir depth: (int) _depth;
- (void) queueTheseFiles: (NSArray *) _filesToQueue depth: (int) _depth;
- (void) queueTheseFiles: (NSArray *) _filesToQueue;
- (void) queueThisFile: (NSString *) mediaURL;
- (void) queueThisFile: (NSString *) mediaURL withOrgURLEntry: (NSString *) _orgURL;

- (void) fetchNextFileFromQueue;
- (BOOL) addThisItemToItunes: (NSMutableDictionary *) mediaDict;
- (oneway void) importCurrentMediaToiTunes: (NSMutableDictionary *) _mediaDict;
- (void) askToRemoveRunningTask: (NSMutableDictionary *) mediaDict;



- (BOOL) isFFmpegAlreadyRunning;


- (IBAction) selectFilesButtonPressed: (id) sender;
- (IBAction) monitorButtonPressed: (id) sender;

- (IBAction) openSettingsWindow: (id) sender;
- (IBAction) resetUserPresets: (id) sender;
- (IBAction) resetUserTVSDRegex: (id) sender;

- (void) monitorActiveQuestion;
- (void) selectMonitorFolder;
- (void) startMonitoringForFolder: (NSString *) _monitorFolder;
- (void) disableMonitoring;


- (void) reQueue: (id) sender;
- (void) removeFromQueue: (id) sender;
- (void) clearQueuePressed: (id) sender;
- (void) stopButtonPressed: (id) sender;


- (void) askForQuit;
- (void) askForStop;


- (void) updateBadge;


- (NSArray *) getArgumentsForPresetNamed: (NSString *) _presetName;
- (NSArray *) parseFfmpegArguments: (id) _argumentsArrayOrString;
- (NSArray *) parseFfmpegArgumentsFromString: (NSString *) _argumentsString;


- (void) doLog: (NSString *) _log;
- (void) doLog: (NSString *) aLogMessage withNewline: (BOOL) withNewLine;


- (void) settings_selectGeneral: (id) sender;
- (void) settings_selectFFMPEGSettings: (id) sender;
- (void) settings_selectMonitorSettings: (id) sender;
- (void) settings_selectTVShowDetection: (id) sender;


- (void) changeMoveMonitoredSuccessFolder: (id) sender;
- (void) changeMoveMonitoredSuccessFolderToDefault: (id) sender;

- (void) changeTempMonitoredFolder: (id) sender;
- (void) changeTempMonitoredFolderToDefault: (id) sender;

- (IBAction) showAboutDialog: (id) sender;

-(void) prepareffmpegBinariesForSettingsView;

@end
