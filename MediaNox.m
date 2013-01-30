//
//  MediaNox.m
//  MediaNox
//
//  Created by Björn Teichmann on 19.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "MediaNox.h"
#import "RegexKitLite.h"

#define restrict
#import <RegexKit/RegexKit.h>

#include "GetPID.h"
#include <Carbon/Carbon.h>

@interface MediaNox ()

@property (nonatomic, retain) FMDatabase *database;

@end

@implementation MediaNox

@synthesize database;

- (id) init {
	if (self = [super init]) {
		NSLog(@"App init");
		[NSApp setDelegate: self];
		[[NSAppleEventManager sharedAppleEventManager] setEventHandler: self andSelector: @selector(handleOpenContentsEvent:replyEvent:) forEventClass:kCoreEventClass andEventID:kAEOpenContents];	
		
		monitorFolderTimer = nil;
		fiveSecondsAgoCheckDate = -1;
                
	}
	return self;
}

- (void) applicationDidFinishLaunching:(NSNotification *)aNotification {
	
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *applicationSupportDirectory = [paths objectAtIndex:0];
    NSString *sqlitePath = [applicationSupportDirectory stringByAppendingPathComponent: @"MediaNox/imports.sqlite"];
    [[NSFileManager defaultManager] createDirectoryAtPath: [sqlitePath stringByDeletingLastPathComponent] withIntermediateDirectories: YES attributes: nil error: NULL];
    
    self.database = [[FMDatabase alloc] initWithPath: sqlitePath];
    [self.database open];
    
    FMResultSet *s = [self.database executeQuery:@"SELECT * FROM imports"];
    if (s == nil) {
        [self.database executeUpdate: @"CREATE TABLE imports (name varchar(255) NOT NULL, PRIMARY KEY (name))"];
    }

    
	NSString *defaultsFile = [[NSBundle mainBundle] pathForResource:@"Defaults" ofType:@"plist"];
	[[NSUserDefaults standardUserDefaults] registerDefaults: [NSDictionary dictionaryWithContentsOfFile: defaultsFile]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkFFMPegStatus:) name:NSTaskDidTerminateNotification object:nil];
	
	ffmpegConvertTask = nil;
	
	[self loadQueue];
	
	// maybe optionally set stoppedState to NO anyway if forced convertStart on launch?!
	
	[self fetchNextFileFromQueue];
	
	[self updateBadge];
	
	[window setAcceptsMouseMovedEvents: YES];
	
	if ([[NSUserDefaults standardUserDefaults] objectForKey: @"monitoredFolder"]) {
		[self startMonitoringForFolder: [[NSUserDefaults standardUserDefaults] objectForKey: @"monitoredFolder"]];
	}
	
	[self prepareffmpegBinariesForSettingsView];
}

-(void) prepareffmpegBinariesForSettingsView {
	// ugly hack, the binaries should sit in an own folder to elminitate confusion of this function
	
	NSString *ffmpegBaseDir = [[[NSBundle mainBundle] pathForResource: @"ffmpeg" ofType: @""] stringByDeletingLastPathComponent];
	
	NSFileManager *fileMan = [NSFileManager defaultManager];

	// look for ffmpeg binaries within the app package
	for (NSString *_files in [[NSFileManager defaultManager] contentsOfDirectoryAtPath: ffmpegBaseDir error: NULL]) {
		NSString *ffmpegBinAbs = [ffmpegBaseDir stringByAppendingPathComponent: _files];
		BOOL isFolder;		
		if ([_files hasPrefix: @"ffmpeg"] && [fileMan fileExistsAtPath:ffmpegBinAbs isDirectory: &isFolder] && !isFolder && [fileMan isExecutableFileAtPath: ffmpegBinAbs]) {
			
			NSString *ffmpegVersionString = [self checkFFmpegVersionforBinary: ffmpegBinAbs];			

			if (ffmpegVersionString) {
				[ffmpegBinaries addObject: [NSDictionary dictionaryWithObjectsAndKeys: _files, @"name", [NSString stringWithFormat: @"builtin ffmpeg (%@)", ffmpegVersionString], @"description", nil]];
			}
		}
	}
	
	// look for ffmpeg binaries on the system paths
	NSMutableArray *systemBinariesToCheck = [NSMutableArray arrayWithObjects: @"/bin/ffmpeg", @"/usr/bin/ffmpeg", @"/usr/local/bin/ffmpeg", @"/opt/local/bin/ffmpeg", nil];
	NSString *localProcessPATH= [[[NSProcessInfo processInfo] environment] objectForKey: @"PATH"];
	if (localProcessPATH) {
		NSArray *localProcessPATHsArray = [localProcessPATH componentsSeparatedByString: @":"];
		if (localProcessPATHsArray)
			for (NSString *localProcessPATHCompontent in localProcessPATHsArray) {
				localProcessPATHCompontent = [localProcessPATHCompontent stringByAppendingPathComponent: @"ffmpeg"];
				if (![systemBinariesToCheck containsObject: localProcessPATHCompontent]) [systemBinariesToCheck addObject:localProcessPATHCompontent];
			}
	}

	for (NSString *_absFiles in systemBinariesToCheck) {
		BOOL isFolder;
		if ([fileMan fileExistsAtPath:_absFiles isDirectory: &isFolder] && !isFolder && [fileMan isExecutableFileAtPath: _absFiles]) {
			
			NSString *ffmpegVersionString = [self checkFFmpegVersionforBinary: _absFiles];			
			
			if (ffmpegVersionString) {
				[ffmpegBinaries addObject: [NSDictionary dictionaryWithObjectsAndKeys: _absFiles, @"name", [NSString stringWithFormat: @"%@ (%@)", _absFiles, ffmpegVersionString], @"description", nil]];
			}
		}
	}	
}

- (NSString *) checkFFmpegVersionforBinary: (NSString *) _ffmpegBin {
	NSTask *ffmpegVersionCheckTask = [[NSTask alloc] init];
	[ffmpegVersionCheckTask setLaunchPath: _ffmpegBin];
	[ffmpegVersionCheckTask setEnvironment: [NSDictionary dictionaryWithObjectsAndKeys: [[NSBundle mainBundle] pathForResource: @"fflibraries" ofType: @""], @"DYLD_LIBRARY_PATH", nil]];
	
	NSPipe *ffmpegVersionCheckPipe = [NSPipe pipe];
	[ffmpegVersionCheckTask setStandardError: ffmpegVersionCheckPipe];
	
	NSFileHandle *ffmpegVersionCheckPipeHandle = [ffmpegVersionCheckPipe fileHandleForReading];
	[ffmpegVersionCheckTask launch];
	
	if (![ffmpegVersionCheckTask isRunning]) {
		NSLog(@"TermStatus: %d", [ffmpegVersionCheckTask terminationStatus]);
		if ([ffmpegVersionCheckTask terminationStatus] != 1) return nil;
	}
	
	NSData *ffmpegVersionCheckOutputData = [ffmpegVersionCheckPipeHandle readDataToEndOfFile];
	if (!ffmpegVersionCheckOutputData) return nil;
	
	NSString *ffmpegVersionCheckOutput = [[[NSString alloc] initWithData: ffmpegVersionCheckOutputData encoding: NSUTF8StringEncoding] autorelease];
	if (!ffmpegVersionCheckOutput) return nil;
	
	NSString *ffmpegVersionString = [ffmpegVersionCheckOutput stringByMatching:@"FFmpeg version ([^,]*)," capture: 1];
	return ffmpegVersionString;
}

- (NSApplicationTerminateReply) applicationShouldTerminate:(NSApplication *)sender {
	if ([self isFFmpegAlreadyRunning]) {
		[self askForQuit];
		return NSTerminateLater;
	}
	return NSTerminateNow;
}

- (void) applicationWillTerminate:(NSNotification *)aNotification {
	[self saveQueue];
	
	[[NSFileManager defaultManager] removeItemAtPath: @"/tmp/MediaNox" error: NULL];
	[[NSFileManager defaultManager] removeItemAtPath: @"/tmp/mp4Convert" error: NULL];
    
    [self.database close];
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication {
	return NO;
}



// handle file drops on the app icon (TODO: handle drops while app isnt opened yet)

- (void) handleOpenContentsEvent: (NSAppleEventDescriptor *) event replyEvent: (NSAppleEventDescriptor *) replyEvent {
	// handle dock drop files
	NSLog(@"Handle dock drop files: %@", event);
	
    NSAppleEventDescriptor * directObject = [event paramDescriptorForKeyword: keyDirectObject];
    if ([directObject descriptorType] == typeAEList) {
        
        for (unsigned i = 1; i <= [directObject numberOfItems]; i++) {
			NSString *urlString = nil;
			if ((urlString = [[directObject descriptorAtIndex: i] stringValue])) {
				[self queueTheseFiles: [NSArray arrayWithObject: urlString]];
			}
		}
		
    } else {
		[self queueTheseFiles: [NSArray arrayWithObject: [directObject stringValue]]];
    }
	
}

- (void) application: (NSApplication *) app openFiles: (NSArray *) filenames {
	// handle dropped files on dock icon
	[self queueTheseFiles: filenames];
}

- (BOOL) applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag {
	if (!flag) [window makeKeyAndOrderFront: self];
	return YES;
}



- (IBAction) resetUserPresets: (id) sender {
	[[NSUserDefaults standardUserDefaults] removeObjectForKey: @"presets"];
}
- (IBAction) resetUserTVSDRegex: (id) sender {
	[[NSUserDefaults standardUserDefaults] removeObjectForKey: @"tvshowparser"];
}


// load and save settings

- (void) saveQueue {
	[[NSUserDefaults standardUserDefaults] setObject: [queueController arrangedObjects] forKey: @"savedQueue"];
	
	[[NSUserDefaults standardUserDefaults] setBool: stoppedState forKey: @"stoppedState"];
}

- (void) loadQueue {
	if ([[NSUserDefaults standardUserDefaults] objectForKey: @"savedQueue"]) {
		for (NSMutableDictionary *queuedDict in [[NSUserDefaults standardUserDefaults] objectForKey: @"savedQueue"]) {
			if([[queuedDict objectForKey: @"status"] intValue] > 0) [queuedDict setObject: [NSNumber numberWithInt: 0] forKey: @"status"];
			[queueController addObject: queuedDict];
		}
	}
	stoppedState = [[NSUserDefaults standardUserDefaults] boolForKey: @"stoppedState"];
	[stopButton setState: stoppedState];
	if (stoppedState) [stopButton setTitle: @"Resume"];
}



// Conversion Queue Management

- (void) stopAllConversionsTasks {
	if (ffmpegConvertTask != nil && [ffmpegConvertTask isRunning]) {
		[ffmpegState setDoubleValue: 0];
		[ffmpegState setCriticalValue: 0];

		[timeLeft setStringValue: @"Calculating time left ..."];
		fiveSecondsAgoCheckDate = -1;

		NSTask *taskToQuit = ffmpegConvertTask;
		ffmpegConvertTask = nil;
		[taskToQuit terminate];
		
		[currentMediaFile setObject: [NSNumber numberWithInt: 0] forKey: @"status"];
		
		// delete the tempFile
		[[NSFileManager defaultManager] removeFileAtPath: [NSString stringWithFormat: @"/tmp/MediaNox/%@.mp4", [[[currentMediaFile objectForKey: @"url"] lastPathComponent] stringByDeletingPathExtension]] handler: nil];
		
		currentMediaFile = nil;
	}
}

- (void) queueTheseFiles: (NSArray *) _filesToQueue {
	[self queueTheseFiles: _filesToQueue depth: 0];
}

- (void) queueTheseFiles: (NSArray *) _filesToQueue inDirectory: (NSString *) _dir depth: (int) _depth {
	NSMutableArray *_tempArray = [[NSMutableArray alloc] initWithCapacity: [_filesToQueue count]];
	
	for (NSString *mediaFileName in _filesToQueue) {
		NSString *_fullFilePath = [_dir stringByAppendingPathComponent: mediaFileName];
		[_tempArray addObject: _fullFilePath];
	}
	
	[self queueTheseFiles: _tempArray depth: _depth];
	
	[_tempArray release];
}

- (void) queueTheseFiles: (NSArray *) _filesToQueue depth: (int) _depth {
	
	for (NSString *mediaURL in _filesToQueue) {
		
		BOOL isDir;
		BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath: mediaURL isDirectory: &isDir];
		
		if (exists) {
			if (isDir) {
				// only go into this subdirectory if depth is ok
				if (_depth == 0) [self queueTheseFiles: [[NSFileManager defaultManager] contentsOfDirectoryAtPath: mediaURL error: NULL] inDirectory: mediaURL depth: (_depth + 1)];
				
			} else {
				[self queueThisFile: mediaURL];
			}
		} else {
			//			[self doLog: [NSString stringWithFormat: @"%@ doesn't exist", mediaURL]];
			
		}
		
	}
	
}

- (void) queueThisFile: (NSString *) mediaURL {
	[self queueThisFile:mediaURL withOrgURLEntry: nil];
}

- (void) queueThisFile: (NSString *) mediaURL withOrgURLEntry: (NSString *) _orgURL {
	if ([[[[NSUserDefaults standardUserDefaults] objectForKey: @"allowed_extensions"] componentsSeparatedByString: @" "] containsObject: [mediaURL pathExtension]]) {
		
		if ([[NSFileManager defaultManager] isReadableFileAtPath: mediaURL]) {
			
			NSString *orgFile = mediaURL;
			
			BOOL isNew = YES;
			for (NSMutableDictionary *nextMediaFile in [queueController arrangedObjects]) if ([[nextMediaFile objectForKey: @"url"] isEqualToString: orgFile]) isNew = NO;
			
			if (isNew) {
				NSString *mediaFileName = [[mediaURL lastPathComponent] stringByDeletingPathExtension];
				NSString *destFile = [NSString stringWithFormat: @"/tmp/MediaNox/%@.mp4", mediaFileName];
				NSString *mediaName = [[mediaURL lastPathComponent] stringByDeletingPathExtension];
				
				NSMutableDictionary *queuedMediaDict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
														mediaName, @"name",
														orgFile, @"url",
														destFile, @"urlDestination",
														@"Movie", @"type",
														[NSNumber numberWithInt: 0], @"status",
														nil];
				
				if (_orgURL && _orgURL.length) {
					[queuedMediaDict setObject: _orgURL forKey: @"orgURL"];
				}
				
				NSLog(@"TPA:%@", [[NSUserDefaults standardUserDefaults] arrayForKey: @"tvshowparser"]);
				BOOL dectectorFailed = YES;
				for (NSDictionary *regExDict in [[NSUserDefaults standardUserDefaults] arrayForKey: @"tvshowparser"]) {
					NSString *regEx = [regExDict objectForKey: @"regex"];
					NSLog(@"Check regex: (%@)", regEx);

					RKEnumerator *regexEnum = [mediaFileName matchEnumeratorWithRegex: regEx];
					if ([regexEnum nextRanges] != NULL) {
						NSLog(@"Matched regex");
						
						int _pCounter = 1;
						NSString *p_name = nil, *p_seasonNo = nil, *p_episodeNo = nil, *p_episodeDesc = nil;
						NSString *rf_name = nil, *rf_seasonNo = nil, *rf_episodeNo = nil, *rf_episodeDesc = nil;
						
						for (NSString *parseChar in [[regExDict objectForKey: @"parse"] componentsSeparatedByString: @","]) {
							if ([parseChar isEqualToString: @"n"]) {
								p_name = [NSString stringWithFormat: @"$%d", _pCounter];
							} else if ([parseChar isEqualToString: @"s"]) {
								p_seasonNo = [NSString stringWithFormat: @"$%d", _pCounter];
							} else if ([parseChar isEqualToString: @"e"]) {
								p_episodeNo = [NSString stringWithFormat: @"$%d", _pCounter];
							} else if ([parseChar isEqualToString: @"d"]) {
								p_episodeDesc = [NSString stringWithFormat: @"$%d", _pCounter];
							}
							_pCounter++;
						}
						
						[regexEnum getCapturesWithReferences: p_name, &rf_name, p_seasonNo, &rf_seasonNo, p_episodeNo, &rf_episodeNo, p_episodeDesc, &rf_episodeDesc, nil];
						
						[queuedMediaDict setObject: @"TV Show" forKey: @"type"];
						[queuedMediaDict setObject: rf_name forKey: @"name"];
						[queuedMediaDict setObject: rf_seasonNo forKey: @"seasonNo"];
						[queuedMediaDict setObject: rf_episodeNo forKey: @"episodeNo"];
						if (rf_episodeDesc != nil) {
							rf_episodeDesc = [rf_episodeDesc stringByReplacingOccurrencesOfRegex: @"([^\\.])\\.([^\\.])" withString: @"$1 $2"];
							rf_episodeDesc = [rf_episodeDesc stringByTrimmingCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @". "]];
							[queuedMediaDict setObject: rf_episodeDesc forKey: @"episodeDesc"];
						}
						
						NSLog(@"Media Detection: TV Show (Season: %@ - Episode: %@ - Description: %@)", rf_seasonNo, rf_episodeNo, rf_episodeDesc);
						dectectorFailed = NO;
						break;
					}
					
				}
				if (dectectorFailed) NSLog(@"Media Detection: Movie");
				
				
				// Trim the Media Name
				NSString *newMediaName = [[queuedMediaDict objectForKey: @"name"] stringByReplacingOccurrencesOfRegex: @"([^\\.])\\.([^\\.])" withString: @"$1 $2"];
				newMediaName = [newMediaName stringByTrimmingCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @". "]];
				[queuedMediaDict setObject: newMediaName forKey: @"name"];
				
				
				if ([[queuedMediaDict objectForKey: @"type"] isEqualToString: @"Movie"]) {
					[queuedMediaDict setObject: [[[NSUserDefaultsController sharedUserDefaultsController] values] valueForKey: @"defaultMoviePreset"] forKey: @"preset"];								
				} else {
					[queuedMediaDict setObject: [[[NSUserDefaultsController sharedUserDefaultsController] values] valueForKey: @"defaultTVShowPreset"] forKey: @"preset"];
				}
				
				
				[queueController addObject: queuedMediaDict];
				
				NSLog(@"Queue: %@", [queueController arrangedObjects]);
				
			} else {
				[self doLog: [NSString stringWithFormat: @"Already in queue: %@", orgFile]];
				
			}
		}
		
		
	} else {
		//					[self doLog: [NSString stringWithFormat: @"%@ is no suitable media file", [mediaURL lastPathComponent]]];
		
	}

	[self fetchNextFileFromQueue];
	[self updateBadge];
}


// Import Tast Management

- (void) fetchNextFileFromQueue {
	if ([self isFFmpegAlreadyRunning]) return;
	if (stoppedState) {
		[stopButton setTitle: @"Resume"];
		return;
	}
	
	for (NSMutableDictionary *nextMediaFile in [queueController arrangedObjects]) {
		if ([[nextMediaFile objectForKey: @"status"] intValue] == 0) [self convertMediaFile: nextMediaFile];
	}
	
	[self updateBadge];
}

- (BOOL) convertMediaFile: (NSMutableDictionary *) mediaDict {
	if ([self isFFmpegAlreadyRunning]) return NO;
	
	currentMediaFile = mediaDict;
	
	// scroll to the row of the item
	int indexOfMedia = [[queueController arrangedObjects] indexOfObject: mediaDict];
	[queueTable scrollRowToVisible: indexOfMedia];


	NSFileManager *fileMan = [NSFileManager defaultManager];
	
	NSString *ffmpegBin = [[NSUserDefaults standardUserDefaults] objectForKey: @"ffmpegBinary"];
	if (!ffmpegBin) ffmpegBin = @"ffmpeg";
	if (![ffmpegBin hasPrefix: @"/"]) ffmpegBin = [[NSBundle mainBundle] pathForResource: ffmpegBin ofType: @""];
	
	if (![fileMan isExecutableFileAtPath: ffmpegBin]) {
		[self doLog: [NSString stringWithFormat: @"Could not find the selected ffmpeg binary (%@)! Probing default...", ffmpegBin]];
		ffmpegBin = [[NSBundle mainBundle] pathForResource: @"ffmpeg" ofType: @""];
		if ([fileMan isExecutableFileAtPath: ffmpegBin]) [self doLog: [NSString stringWithFormat: @"... using default!"]];
		else {
			[self doLog: [NSString stringWithFormat: @"Could not find any suitable ffmpeg binary! Aborting..."]];
			return NO;
		}
	}
	
	
	NSString *orgFile = [mediaDict objectForKey: @"url"];
	NSString *destFile = [mediaDict objectForKey: @"urlDestination"];
	
	
	[[NSFileManager defaultManager] createDirectoryAtPath: [destFile stringByDeletingLastPathComponent] withIntermediateDirectories: YES attributes: nil error: NULL];
	
	
	// get the movie aspect ratio
	
	NSMutableArray *ffmpegArgArray = [NSMutableArray arrayWithObjects: @"-i", orgFile, nil];
	
	NSTask *_movieInfo_ffmpegTask = [[NSTask alloc] init];
	[_movieInfo_ffmpegTask setLaunchPath: ffmpegBin];
	[_movieInfo_ffmpegTask setArguments: ffmpegArgArray];
	[_movieInfo_ffmpegTask setCurrentDirectoryPath: [ffmpegBin stringByDeletingLastPathComponent]];
	[_movieInfo_ffmpegTask setEnvironment: [NSDictionary dictionaryWithObjectsAndKeys: [[NSBundle mainBundle] pathForResource: @"fflibraries" ofType: @""], @"DYLD_LIBRARY_PATH", nil]];
	
	NSPipe *_movieInfo_ffmpegOutputPipe = [NSPipe pipe];
    [_movieInfo_ffmpegTask setStandardError: _movieInfo_ffmpegOutputPipe];
	
	NSFileHandle *_movieInfo_ffmpegOutputPipeHandle = [_movieInfo_ffmpegOutputPipe fileHandleForReading];
	[_movieInfo_ffmpegTask launch];
	
	NSData *_movieInfo_ffmpegOutputData = [_movieInfo_ffmpegOutputPipeHandle readDataToEndOfFile];
	
	NSString *_movieInfo_ffmpegOutputString = [[NSString alloc] initWithData: _movieInfo_ffmpegOutputData encoding: NSUTF8StringEncoding];
	
	// get the video aspect ratio
	NSString *videoAspectRation = [_movieInfo_ffmpegOutputString stringByMatching:@"Video:.*[^0-9]([0-9]+x[0-9]+)" capture: 1];
	videoAspectRation = [videoAspectRation stringByReplacingOccurrencesOfString:@"x" withString: @":"];
	
	// get the video duration
	NSString *videoDuration = [_movieInfo_ffmpegOutputString stringByMatching:@"Duration: ([^,]*)," capture: 1];
	int videoDurationInSeconds = 0;
	NSArray *videoDurationArray = [videoDuration componentsSeparatedByString: @":"];
	for (int _counter = 0 ; _counter < [videoDurationArray count]; _counter++) {
		if (_counter == 0) videoDurationInSeconds += ([[videoDurationArray objectAtIndex: _counter] floatValue] * 3600);
		else if (_counter == 1) videoDurationInSeconds += ([[videoDurationArray objectAtIndex: _counter] floatValue] * 60);
		else if (_counter == 2) videoDurationInSeconds += [[videoDurationArray objectAtIndex: _counter] floatValue];
	}
	
	[_movieInfo_ffmpegOutputString release];
	
	//	[self doLog: [NSString stringWithFormat: @"MovieInfo: %@", _movieInfo_ffmpegOutputString]];
	//	[self doLog: [NSString stringWithFormat: @"MovieInfoAspectRatio: %@", videoAspectRation]];
	
	
	// create the convertion arguments for ffmpeg
	[ffmpegArgArray addObjectsFromArray: [NSArray arrayWithObjects: @"-aspect", videoAspectRation, nil]];	// the calculated video aspect ratio
	[ffmpegArgArray addObjectsFromArray: [self parseFfmpegArguments: [[NSUserDefaults standardUserDefaults] stringForKey: @"ffmpegStandardArgs"]]];
	[ffmpegArgArray addObjectsFromArray: [self getArgumentsForPresetNamed: [mediaDict objectForKey: @"preset"]]];
	
	// add the h264 metadata
	if ([[mediaDict objectForKey: @"type"] isEqualToString: @"Movie"]) {
		[ffmpegArgArray addObjectsFromArray: [NSArray arrayWithObjects: @"-metadata", [NSString stringWithFormat: @"title=%@", [mediaDict objectForKey: @"name"]], nil]];
		[ffmpegArgArray addObjectsFromArray: [NSArray arrayWithObjects: @"-metadata", [NSString stringWithFormat: @"comment=OrgFileName: %@", [[mediaDict objectForKey: @"url"] lastPathComponent]], nil]];
		
	} else if ([[mediaDict objectForKey: @"type"] isEqualToString: @"TV Show"]) {
		[ffmpegArgArray addObjectsFromArray: [NSArray arrayWithObjects: @"-metadata", [NSString stringWithFormat: @"title=%@ S%@E%@", [mediaDict objectForKey: @"name"], [mediaDict objectForKey: @"seasonNo"], [mediaDict objectForKey: @"episodeNo"]], nil]];
		[ffmpegArgArray addObjectsFromArray: [NSArray arrayWithObjects: @"-metadata", [NSString stringWithFormat: @"comment=OrgFileName: %@ | %@", [[mediaDict objectForKey: @"url"] lastPathComponent], [mediaDict objectForKey: @"episodeDesc"]], nil]];
		[ffmpegArgArray addObjectsFromArray: [NSArray arrayWithObjects: @"-metadata", [NSString stringWithFormat: @"album=%@", [mediaDict objectForKey: @"name"]], nil]];
		[ffmpegArgArray addObjectsFromArray: [NSArray arrayWithObjects: @"-metadata", [NSString stringWithFormat: @"track=%@", [mediaDict objectForKey: @"episodeNo"]], nil]];

	}
	
	[ffmpegArgArray addObject: destFile];	// finally add the output filename
	
	
	// run ffmpeg for conversion
	
	ffmpegConvertTask = [[NSTask alloc] init];
	[ffmpegConvertTask setLaunchPath: ffmpegBin];
	[ffmpegConvertTask setArguments: ffmpegArgArray];
	[ffmpegConvertTask setCurrentDirectoryPath: [ffmpegBin stringByDeletingLastPathComponent]];
	[ffmpegConvertTask setEnvironment: [NSDictionary dictionaryWithObjectsAndKeys: [[NSBundle mainBundle] pathForResource: @"fflibraries" ofType: @""], @"DYLD_LIBRARY_PATH", nil]];
	
	
	NSPipe *_conversion_ffmpegOutputPipe = [NSPipe pipe];
	//    [ffmpegConvertTask setStandardOutput: _conversion_ffmpegOutputPipe];
    [ffmpegConvertTask setStandardError: _conversion_ffmpegOutputPipe];
	
	[ffmpegConvertTask launch];
	
	[ffmpegState setMaxValue: videoDurationInSeconds];
	[ffmpegState setCriticalValue: 0];
	
	[currentMediaFile setObject: [NSNumber numberWithInt: 1] forKey: @"status"];
	
	[NSThread detachNewThreadSelector:@selector( readFFMPEGOutput: ) toTarget:self withObject: _conversion_ffmpegOutputPipe];
	
	[self doLog: [NSString stringWithFormat: @"--- Converting: %@ ---", [mediaDict objectForKey: @"name"]]];
	
	[self updateBadge];
	
	return YES;
}

- (oneway void) importConvertedMediaToFolder: (NSMutableDictionary *) _mediaDict {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	// the source
	NSString *convertedFilePath = [_mediaDict objectForKey: @"urlDestination"];
	
	// build the destination path
	NSString *seasonString = [_mediaDict objectForKey: @"seasonNo"];
	NSString *episodeString = [_mediaDict objectForKey: @"episodeNo"];
	if (seasonString && seasonString.length == 1) seasonString = [@"0" stringByAppendingString: seasonString];
	if (episodeString && episodeString.length == 1) episodeString = [@"0" stringByAppendingString: episodeString];
	
	NSString *destFileNameComplete;
	if ([[_mediaDict objectForKey: @"type"] isEqualToString: @"Movie"]) destFileNameComplete = [NSString stringWithFormat: @"%@.mp4", [_mediaDict objectForKey: @"name"]];
	else if ([[_mediaDict objectForKey: @"type"] isEqualToString: @"TV Show"]) destFileNameComplete = [NSString stringWithFormat: @"%@ [S%@E%@] %@.mp4", [_mediaDict objectForKey: @"name"], seasonString, episodeString, [_mediaDict objectForKey: @"episodeDesc"]];
	
	NSString *fullFileDest = [[[NSUserDefaults standardUserDefaults] stringForKey: @"importDestination"] stringByAppendingPathComponent: destFileNameComplete];

	
	[[NSFileManager defaultManager] createDirectoryAtPath: [fullFileDest stringByDeletingLastPathComponent] withIntermediateDirectories: YES attributes: nil error: NULL];
	[[NSFileManager defaultManager] removeFileAtPath:fullFileDest handler: nil];
	[[NSFileManager defaultManager] moveItemAtPath: convertedFilePath toPath: fullFileDest error: NULL];

	[currentMediaFile setObject: [NSNumber numberWithInt: -1] forKey: @"status"];

	[self performSelectorOnMainThread:@selector( doLog: ) withObject:@"Import done" waitUntilDone:NO];
	[self performSelectorOnMainThread:@selector( fetchNextFileFromQueue ) withObject: nil waitUntilDone:NO];
	
	[pool release];		
}

- (oneway void) importConvertedMediaToiTunes: (NSMutableDictionary *) _mediaDict {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	// load the script from a resource by fetching its URL from within our bundle
    NSString* path = [[NSBundle mainBundle] pathForResource:@"iTunesImport" ofType:@"scpt"];
	
    if (path != nil) {
        NSURL* url = [NSURL fileURLWithPath:path];
        if (url != nil) {
			
            NSDictionary* errors = [NSDictionary dictionary];
            NSAppleScript* appleScript = [[NSAppleScript alloc] initWithContentsOfURL:url error:&errors];
			
            if (appleScript != nil) {
				
                // create the AppleEvent target
                ProcessSerialNumber psn = {0, kCurrentProcess};
                NSAppleEventDescriptor* target = [NSAppleEventDescriptor descriptorWithDescriptorType:typeProcessSerialNumber bytes:&psn length:sizeof(ProcessSerialNumber)];
				
                // create the event for an AppleScript subroutine,
                // set the method name and the list of parameters
                NSAppleEventDescriptor* event = [NSAppleEventDescriptor appleEventWithEventClass:kASAppleScriptSuite eventID:kASSubroutineEvent targetDescriptor:target returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
				
				// create and populate the list of parameters (in our case just one)
                NSAppleEventDescriptor* parameters = [NSAppleEventDescriptor listDescriptor];
				
				if ([[_mediaDict objectForKey: @"type"] isEqualToString: @"Movie"]) {
					[event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString: [@"importMovie" lowercaseString]] forKeyword:keyASSubroutineName];
					[parameters insertDescriptor:[NSAppleEventDescriptor descriptorWithString: [_mediaDict objectForKey: @"urlDestination"]] atIndex:1];
					[parameters insertDescriptor:[NSAppleEventDescriptor descriptorWithString: [[_mediaDict objectForKey: @"url"] lastPathComponent]] atIndex:2];
					[parameters insertDescriptor:[NSAppleEventDescriptor descriptorWithString: [_mediaDict objectForKey: @"name"]] atIndex:3];
					
				} else if ([[_mediaDict objectForKey: @"type"] isEqualToString: @"TV Show"]) {
					[event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString: [@"importTVShow" lowercaseString]] forKeyword:keyASSubroutineName];
					[parameters insertDescriptor:[NSAppleEventDescriptor descriptorWithString: [_mediaDict objectForKey: @"urlDestination"]] atIndex:1];
					[parameters insertDescriptor:[NSAppleEventDescriptor descriptorWithString: [[_mediaDict objectForKey: @"url"] lastPathComponent]] atIndex:2];
					[parameters insertDescriptor:[NSAppleEventDescriptor descriptorWithString: [_mediaDict objectForKey: @"name"]] atIndex:3];
					[parameters insertDescriptor:[NSAppleEventDescriptor descriptorWithInt32: [[_mediaDict objectForKey: @"seasonNo"] intValue]] atIndex:4];
					[parameters insertDescriptor:[NSAppleEventDescriptor descriptorWithInt32: [[_mediaDict objectForKey: @"episodeNo"] intValue]] atIndex:5];
					[parameters insertDescriptor:[NSAppleEventDescriptor descriptorWithString: [_mediaDict objectForKey: @"episodeDesc"]] atIndex:6];
					
				}
				
				[event setParamDescriptor:parameters forKeyword:keyDirectObject];
				
                // call the event in AppleScript
                if ([appleScript executeAppleEvent:event error:&errors]) {
					[self performSelectorOnMainThread:@selector( doLog: ) withObject:@"iTunes import done" waitUntilDone:NO];
					[currentMediaFile setObject: [NSNumber numberWithInt: -1] forKey: @"status"];
					
					// delete the converted file (only on success, the failed will be removed on app close anyway)
					[[NSFileManager defaultManager] removeFileAtPath: [_mediaDict objectForKey: @"urlDestination"] handler: nil];
					
					[self performSelectorOnMainThread:@selector( finalizeCurrentImport ) withObject: nil waitUntilDone:YES];
					
				} else {
                    // report any errors from 'errors'
					
					[self performSelectorOnMainThread:@selector( doLog: ) withObject: [NSString stringWithFormat: @"iTunes import failed - %@", errors] waitUntilDone:NO];
					[currentMediaFile setObject: [NSNumber numberWithInt: -3] forKey: @"status"];
					
				}
				
                [appleScript release];
				
            } else {
                // report any errors from 'errors'
				[self performSelectorOnMainThread:@selector( doLog: ) withObject: [NSString stringWithFormat: @"Applescript Error: %@", errors] waitUntilDone:NO];
            }
			
			[self performSelectorOnMainThread:@selector( fetchNextFileFromQueue ) withObject: nil waitUntilDone:NO];
			
        } else {
			[self performSelectorOnMainThread:@selector( doLog: ) withObject:@"iTunesImport Script nicht gefunden (1)" waitUntilDone:NO];
		}
		
    } else {
		[self performSelectorOnMainThread:@selector( doLog: ) withObject:@"iTunesImport Script nicht gefunden (2)" waitUntilDone:NO];
	}
	
	[pool release];		
}

- (void) finalizeCurrentImport {
	if ([[NSUserDefaults standardUserDefaults] integerForKey: @"moveMonitoredSuccessMode"] == 1) {
		
		// do nothing
		
	} else if ([[NSUserDefaults standardUserDefaults] integerForKey: @"moveMonitoredSuccessMode"] == 2) {

		// move file
		NSString *moveFileToTempDir = nil;
		if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"moveMonitoredSuccessFolder"] hasPrefix: @"/"]) {
			moveFileToTempDir = [[NSUserDefaults standardUserDefaults] stringForKey: @"moveMonitoredSuccessFolder"];
		} else {
			NSString *_orgURL = [currentMediaFile objectForKey: @"url"];
			if ([currentMediaFile objectForKey: @"orgURL"]) {
				_orgURL = [currentMediaFile objectForKey: @"orgURL"];
			}
			
			moveFileToTempDir = [[_orgURL stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"imported"];
		}
		
		[[NSFileManager defaultManager] createDirectoryAtPath: moveFileToTempDir withIntermediateDirectories: YES attributes: nil error: NULL];
		
		NSString *finalFileName = [moveFileToTempDir stringByAppendingPathComponent: [[currentMediaFile objectForKey: @"url"] lastPathComponent]];

		[[NSFileManager defaultManager] moveItemAtPath:[currentMediaFile objectForKey: @"url"] toPath: finalFileName error: NULL];

	} else if ([[NSUserDefaults standardUserDefaults] integerForKey: @"moveMonitoredSuccessMode"] == 3) {

		// delete file
		NSString *sourceFile = [currentMediaFile objectForKey: @"url"];
		
		FSRef sourceFileRef;
		OSStatus err = FSPathMakeRef((const UInt8 *)[sourceFile fileSystemRepresentation], &sourceFileRef, NULL);
		if(err == noErr) {
			FSMoveObjectToTrashSync(&sourceFileRef, NULL, kFSFileOperationDefaultOptions);
			[self doLog: [NSString stringWithFormat: @"Moving %@ to Trash", [currentMediaFile objectForKey: @"name"]]];
		} else {
			[self doLog: [NSString stringWithFormat: @"Moving %@ to Trash failed!", [currentMediaFile objectForKey: @"name"]]];
		}
		
	}
}

- (void) askToRemoveRunningTask: (NSMutableDictionary *) mediaDict {
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert addButtonWithTitle:@"Stop and remove"];
	[alert addButtonWithTitle:@"Cancel"];
	[alert setMessageText:@"Are you sure?"];
	[alert setInformativeText:@"This task is already started and will be aborted!"];
	[alert setAlertStyle:NSWarningAlertStyle];
	[alert beginSheetModalForWindow: window modalDelegate:self didEndSelector:@selector(askToRemoveRunningTaskAlertDidEnd:returnCode:contextInfo:) contextInfo:mediaDict];
}

- (void) askToRemoveRunningTaskAlertDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(NSMutableDictionary *) mediaDict {
	if (returnCode == NSAlertFirstButtonReturn) {
		[self stopAllConversionsTasks];
		[queueController removeObject: mediaDict];
		[self fetchNextFileFromQueue];
	}
}



// Conversion/ffmpeg Addons

- (oneway void) readFFMPEGOutput: (NSPipe *) _pipe {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSData *data;
	while([data = [[_pipe fileHandleForReading] availableData] length]) { // until EOF (check reference)
		NSString *string = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
		
		// get the video duration
		NSString *videoTime = [string stringByMatching:@"time=(\\S+)\\s" capture: 1];
		if (videoTime != nil && videoTime.length) [self performSelectorOnMainThread:@selector( setFFMPEGstatus: ) withObject:videoTime waitUntilDone:NO];
		
		NSString *_bitrate = [string stringByMatching:@"bitrate=(.+)kbit" capture: 1];
		if (_bitrate != nil && _bitrate.length) [self performSelectorOnMainThread:@selector( setFFMPEGbitrate: ) withObject:_bitrate waitUntilDone:NO];
		
		NSString *_stopEncoding = [string stringByMatching: @"to stop encoding"];
		
		if ((_stopEncoding == nil || _stopEncoding.length == 0) && (_bitrate == nil || _bitrate.length == 0) && (videoTime == nil || videoTime.length == 0)) {
			if ([[[[NSUserDefaultsController sharedUserDefaultsController] values] valueForKey: @"showFFMPEGOutput"] boolValue]) {
				NSString *outPut = string;
				[self performSelectorOnMainThread: @selector(doLogWithoutNewline:) withObject: [NSString stringWithFormat: @"%@", outPut] waitUntilDone: NO];
			}
		}
		
		[string release];
	}
	[pool release];		
}

- (void) checkFFMPegStatus:(NSNotification *)aNotification {
	NSTask *_currentFFMPEGTask = [aNotification object];
	
	// only monitor the ffmpegConvertTask
	if (ffmpegConvertTask != nil && _currentFFMPEGTask == ffmpegConvertTask) {
		
		ffmpegConvertTask = nil;
		
		int status = [_currentFFMPEGTask terminationStatus];
		if (status == 0) {
			[self doLog: @"Convert done"];
			[currentMediaFile setObject: [NSNumber numberWithInt: 2] forKey: @"status"];
			[ffmpegState setDoubleValue: 0];
			[ffmpegState setCriticalValue: 0];
			
			if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"importDestination"] isEqualToString: @"iTunes"]) {
				[NSThread detachNewThreadSelector:@selector( importConvertedMediaToiTunes: ) toTarget:self withObject: currentMediaFile];
			} else {
				[NSThread detachNewThreadSelector:@selector( importConvertedMediaToFolder: ) toTarget:self withObject: currentMediaFile];
			}
			
		} else {
			[self doLog: @"Convert failed"];
			[currentMediaFile setObject: [NSNumber numberWithInt: -2] forKey: @"status"];
			[ffmpegState setCriticalValue: [ffmpegState doubleValue]];
			
			currentMediaFile = nil;
			
			
			[self doLog: [NSString stringWithFormat: @"FFMPEG failed with state: %d", [_currentFFMPEGTask terminationStatus]]];
			
			[self fetchNextFileFromQueue];
		}
		
		[timeLeft setStringValue: @"Calculating time left ..."];
		fiveSecondsAgoCheckDate = -1;

		[self updateBadge];
		
	}
	
	[_currentFFMPEGTask release];	
}

- (BOOL) isFFmpegAlreadyRunning {
	if (ffmpegConvertTask != nil && [ffmpegConvertTask isRunning]) return YES;
	
	const int kPIDArrayLength = 10;
	pid_t myArray[kPIDArrayLength];
	unsigned int numberMatches;
	int error = GetAllPIDsForProcessName("ffmpeg", myArray, kPIDArrayLength, &numberMatches, NULL);
	if (error == 0) { // Success
		if (numberMatches > 1) {
			return YES;
		}
	}
	
	// check the queuedObjects' states
	for (NSMutableDictionary *nextMediaFile in [queueController arrangedObjects]) {
		if ([[nextMediaFile objectForKey: @"status"] intValue] > 0) return YES;
	}
	
	return NO;
}



//// UI Button Presses

- (IBAction) selectFilesButtonPressed: (id) sender {
	NSOpenPanel *selectFilesDialog = [NSOpenPanel openPanel];
	[selectFilesDialog setCanChooseFiles: YES];
	[selectFilesDialog setCanChooseDirectories: YES];
	[selectFilesDialog setAllowsMultipleSelection: YES];

	[selectFilesDialog beginSheetForDirectory: nil file: nil types: [[[NSUserDefaults standardUserDefaults] objectForKey: @"allowed_extensions"] componentsSeparatedByString: @" "] modalForWindow: window modalDelegate: self didEndSelector: @selector(selectFilesDialogDidEnd:returnCode:contextInfo:) contextInfo: nil];
	
}

- (void) selectFilesDialogDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode contextInfo:(void  *)contextInfo {
	if (returnCode == NSOKButton) {
		[self queueTheseFiles: [panel filenames] depth: 0];
	}
}

- (IBAction) monitorButtonPressed: (id) sender {
	if (monitorFolderTimer != nil) {
		[self monitorActiveQuestion];
	} else {
		[self selectMonitorFolder];
	}
}



// Monitor Functions

- (void) monitorActiveQuestion {
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert addButtonWithTitle:@"Change Monitor Folder"];
	[alert addButtonWithTitle:@"Stop Monitoring"];
	[alert addButtonWithTitle:@"Cancel"];
	[alert setMessageText:@"Monitoring already active"];
	[alert setInformativeText:@"Choose what you want to do"];
	[alert setAlertStyle:NSWarningAlertStyle];
	[alert beginSheetModalForWindow: window modalDelegate:self didEndSelector:@selector(monitorActiveQuestionAlertDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

- (void) monitorActiveQuestionAlertDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(void *)contextInfo {
	[[alert window] orderOut: alert]; // to chain this alert with the selectMonitor alert
	
	if (returnCode == NSAlertFirstButtonReturn) {
		[self selectMonitorFolder]; 
	} else if (returnCode == NSAlertSecondButtonReturn) {
		[self disableMonitoring];
	}
}

- (void) selectMonitorFolder {
	NSOpenPanel *selectMonitorFolderDialog = [NSOpenPanel openPanel];
	[selectMonitorFolderDialog setCanChooseFiles: NO];
	[selectMonitorFolderDialog setCanChooseDirectories: YES];
	[selectMonitorFolderDialog setAllowsMultipleSelection: NO];

	[selectMonitorFolderDialog beginSheetForDirectory: nil file: nil types: nil modalForWindow: window modalDelegate: self didEndSelector: @selector(selectMonitorFolderDialogDidEnd:returnCode:contextInfo:) contextInfo: nil];
}

- (void) selectMonitorFolderDialogDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode contextInfo:(void  *)contextInfo {
	if (returnCode == NSOKButton) {
		if ([panel filenames].count) {
			NSString *monitorFolder = [[panel filenames] objectAtIndex: 0];
			[self startMonitoringForFolder: monitorFolder];
		}
	}
}

- (void) startMonitoringForFolder: (NSString *) _monitorFolder {
	[[NSUserDefaults standardUserDefaults] setObject: _monitorFolder forKey: @"monitoredFolder"];
	
	if (monitorFolderTimer != nil) [monitorFolderTimer invalidate];
	monitorFolderTimer = [[NSTimer alloc] initWithFireDate: [NSDate date] interval:30 target: self selector: @selector(checkMonitoredFolder:) userInfo: _monitorFolder repeats: YES];
	[[NSRunLoop currentRunLoop] addTimer: monitorFolderTimer forMode: NSDefaultRunLoopMode];
	
	[monitorWheel startAnimation: self];
	
	[self doLog: [NSString stringWithFormat: @"Now monitoring: %@", _monitorFolder]];	
}

- (void) checkMonitoredFolder: (NSTimer *) _timer {
	NSString *monitorPath = [_timer userInfo];
	
	BOOL isFolder;
	if (![[NSFileManager defaultManager] fileExistsAtPath: monitorPath isDirectory: &isFolder]) {
		[self doLog: [NSString stringWithFormat: @"Monitored folder '%@' doesn't exist. Disabling monitoring.", monitorPath]];
		[self disableMonitoring];
		return;
	} else {
		if (!isFolder) {
			[self doLog: [NSString stringWithFormat: @"Monitored path '%@' is not a folder. Disabling monitoring.", monitorPath]];
			[self disableMonitoring];			
			return;
		}
	}
	
	NSArray *monitorFolderContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: monitorPath error: NULL];
	
	for (NSString *monitorFolderContentFile in monitorFolderContents) {
		if ([[[[NSUserDefaults standardUserDefaults] objectForKey: @"allowed_extensions"] componentsSeparatedByString: @" "] containsObject: [monitorFolderContentFile pathExtension]]) {
			
            if (![[self.database executeQuery: @"SELECT * FROM imports WHERE name = ?", monitorFolderContentFile] next]) {
                NSString *filePath = [monitorPath stringByAppendingPathComponent: monitorFolderContentFile];
                NSLog(@"Found new file: %@", filePath);
                [self queueThisFile: filePath];
                
                [self.database executeUpdate:@"INSERT INTO imports VALUES (?)",monitorFolderContentFile];
            }
			
		}
		
	}
	
}

- (void) disableMonitoring {
	if (monitorFolderTimer != nil) {
		[monitorFolderTimer invalidate];
		monitorFolderTimer = nil;
	}
	
	[[NSUserDefaults standardUserDefaults] removeObjectForKey: @"monitoredFolder"];
	[monitorWheel stopAnimation: self];
}




// QueueTable Button Presses

- (void) reQueue: (id) sender {
	NSMutableDictionary *mediaDict = [[queueController arrangedObjects] objectAtIndex: [(NSTableView *)sender selectedRow]];
	if ([[mediaDict objectForKey: @"status"] intValue] < 0) [mediaDict setObject: [NSNumber numberWithInt: 0] forKey: @"status"];
	
	[self fetchNextFileFromQueue];
}

- (void) removeFromQueue: (id) sender {
	NSMutableDictionary *mediaDict = [[queueController arrangedObjects] objectAtIndex: [(NSTableView *)sender selectedRow]];
	
	if ([[mediaDict objectForKey: @"status"] intValue] > 0) [self askToRemoveRunningTask: mediaDict];
	else [queueController removeObjectAtArrangedObjectIndex: [(NSTableView *)sender selectedRow]];
	
}

- (void) clearQueuePressed: (id) sender {
	NSMutableArray *toDelete = [NSMutableArray arrayWithCapacity: [[queueController arrangedObjects] count]];
	
	for (NSMutableDictionary *nextMediaFile in [queueController arrangedObjects]) {
		int _status = [[nextMediaFile objectForKey: @"status"] intValue];
		if (_status < 1) [toDelete addObject: nextMediaFile];
	}
	
	[queueController removeObjects: toDelete];
}

- (void) stopButtonPressed: (id) sender {
	if ([sender state]) {
		[self askForStop];
	} else {
		[stopButton setTitle: @"Stop"];
		stoppedState = NO;
		[self fetchNextFileFromQueue];		
	}
	
	[self updateBadge];
}



// UI Alerts

- (void) askForQuit {
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert addButtonWithTitle:@"OK"];
	[alert addButtonWithTitle:@"Cancel"];
	[alert setMessageText:@"Are you sure?"];
	[alert setInformativeText:@"Theres currently a convertion task running.\nQuitting now will stop this task and needs to restart it from the beginning next time!"];
	[alert setAlertStyle:NSWarningAlertStyle];
	[alert beginSheetModalForWindow: window modalDelegate:self didEndSelector:@selector(askForQuitAlertDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

- (void) askForQuitAlertDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(void *)contextInfo {
	if (returnCode == NSAlertFirstButtonReturn) {
		[self stopAllConversionsTasks];
		[[NSApplication sharedApplication] replyToApplicationShouldTerminate: YES];
	} else {
		[[NSApplication sharedApplication] replyToApplicationShouldTerminate: NO];			
	}
}


- (void) askForStop {
	if (ffmpegConvertTask != nil && [ffmpegConvertTask isRunning]) {
		[stopButton setEnabled: NO];

		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert addButtonWithTitle:@"Stop after current task"];
		[alert addButtonWithTitle:@"Stop now"];
		[alert addButtonWithTitle:@"Cancel"];
		[alert setMessageText:@"Are you sure?"];
		[alert setInformativeText:@"Stopping now will need to restart the task from the beginning next time - you should prefer to stop after the current task!"];
		[alert setAlertStyle:NSWarningAlertStyle];
		[alert beginSheetModalForWindow: window modalDelegate:self didEndSelector:@selector(askForStopAlertDidEnd:returnCode:contextInfo:) contextInfo:nil];
	} else {
		[stopButton setTitle: @"Resume"];
		stoppedState = YES;
	}

	[self updateBadge];
}

- (void) askForStopAlertDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(void *)contextInfo {
	if (returnCode == NSAlertFirstButtonReturn) {
		stoppedState = YES;
		[stopButton setTitle: @"Waiting"];
		
	} else if (returnCode == NSAlertSecondButtonReturn) {
		stoppedState = YES;
		[self stopAllConversionsTasks];
		[stopButton setTitle: @"Resume"];
	} else {
		[stopButton setState: 0];
		[stopButton setTitle: @"Stop"];
	}
	[stopButton setEnabled: YES];
	
	[self updateBadge];
}
		


// UI Outbound Actions

- (void) setFFMPEGbitrate: (NSString *) _bitrate {
	if (ffmpegConvertTask != nil && [ffmpegConvertTask isRunning]) [ffmpegBitrate setStringValue: [NSString stringWithFormat: @"%@ kbit/s", _bitrate]];	
}

- (void) setFFMPEGstatus: (NSString *) _videoTimeString {
	if (ffmpegConvertTask != nil && [ffmpegConvertTask isRunning]) {

		// set elapsed conversion time for the progress bar
		double ffmpegTimeDone = [_videoTimeString doubleValue];
		[ffmpegState setDoubleValue: ffmpegTimeDone];

		// calculate the remaining time
		if (fiveSecondsAgoCheckDate != -1) {
			NSTimeInterval timePassedInSeconds = [NSDate timeIntervalSinceReferenceDate] - fiveSecondsAgoCheckDate;

			int secondsToLetPass = 5;
			if (timePassedInSeconds > secondsToLetPass) {
				double amountProcessedInThisTime = ffmpegTimeDone - fiveSecondsAgoCheckCTime;
				double leftAmountToWorkUp = [ffmpegState maxValue] - ffmpegTimeDone;
				int calculatedSecondsToGo = (int)(leftAmountToWorkUp * secondsToLetPass) / amountProcessedInThisTime;
				
				int _hours = floor(calculatedSecondsToGo / 3600);
				int _minutes = floor((calculatedSecondsToGo - (_hours * 3600)) / 60);
				int _seconds = calculatedSecondsToGo - (_minutes * 60) - (_hours * 3600);
				
				NSString *outPut;
				if (_hours > 0) outPut = [NSString stringWithFormat: @"~ %dh %dm %ds left", _hours, _minutes, _seconds];
				else if (_minutes > 0) outPut = [NSString stringWithFormat: @"~ %dm %ds left", _minutes, _seconds];
				else outPut = [NSString stringWithFormat: @"~ %ds left", _seconds];

				[timeLeft setStringValue: outPut];
				
				fiveSecondsAgoCheckDate = [NSDate timeIntervalSinceReferenceDate];
				fiveSecondsAgoCheckCTime = ffmpegTimeDone;
			}
		} else {
			fiveSecondsAgoCheckDate = [NSDate timeIntervalSinceReferenceDate];
			fiveSecondsAgoCheckCTime = ffmpegTimeDone;
		}
			
	}
}




// UI Dock Icon Functions

- (void) updateBadge {
	int counter = 0;
	for (NSMutableDictionary *nextMediaFile in [queueController arrangedObjects]) {
		int _status = [[nextMediaFile objectForKey: @"status"] intValue];
		if (_status >= 0) counter++;
	}
	
	if ([self isFFmpegAlreadyRunning]) {
		[[[NSApplication sharedApplication] dockTile] setBadgeLabel: [NSString stringWithFormat: @"%d", counter]];
	} else if (stoppedState || counter > 0) {
		[[[NSApplication sharedApplication] dockTile] setBadgeLabel: @"⌦"];
	} else {
		[[[NSApplication sharedApplication] dockTile] setBadgeLabel: nil];
	}
}



// Presets Functions

- (NSArray *) getArgumentsForPresetNamed: (NSString *) _presetName {
	NSDictionary *presetsDict = [[NSUserDefaults standardUserDefaults] objectForKey: @"presets"];

	for (NSDictionary *moviePreset in presetsDict) {
		if ([[moviePreset objectForKey: @"description"] isEqualToString: _presetName]) {
			NSArray *ffmpegMoviePresetArguments = [self parseFfmpegArguments: [moviePreset objectForKey: @"arguments"]];
			return ffmpegMoviePresetArguments;
		}
	}
	
	return nil;
}

- (NSArray *) parseFfmpegArguments: (id) _argumentsArrayOrString {
	NSMutableArray *finalArguments = [NSMutableArray arrayWithCapacity: 20];
	
	if ([_argumentsArrayOrString isKindOfClass: NSClassFromString(@"NSArray")]) {
		for (NSString *_argumentString in _argumentsArrayOrString) {
			[finalArguments addObjectsFromArray: [self parseFfmpegArgumentsFromString: _argumentString]];
		}
		
	} else if ([_argumentsArrayOrString isKindOfClass: NSClassFromString(@"NSString")]) {
		[finalArguments addObjectsFromArray: [self parseFfmpegArgumentsFromString: _argumentsArrayOrString]];		
		
	}
	
	return finalArguments;
}

- (NSArray *) parseFfmpegArgumentsFromString: (NSString *) _argumentString {
	NSMutableArray *finalArguments = [NSMutableArray arrayWithCapacity: 20];
	
	NSArray *_argumentComponents = [_argumentString componentsSeparatedByString: @" -"]; // find all ffmpeg arguments by splitting
	for (NSString *_argumentComponent in _argumentComponents) {
		int firstSpaceLocation = [_argumentComponent rangeOfString: @" "].location;
		if (firstSpaceLocation != NSNotFound && firstSpaceLocation != -1) {
			// this ffmpeg argument comes with a variable
            
            NSLog(@"fs %d in: (%@)", firstSpaceLocation, _argumentComponent);
			
			NSString *_argumentPart1 = [_argumentComponent substringToIndex: firstSpaceLocation];
			if (![_argumentPart1 hasPrefix: @"-"]) _argumentPart1 = [NSString stringWithFormat: @"-%@", _argumentPart1]; // eventually add the missing prefix again, caused by the split
			_argumentPart1 = [_argumentPart1 stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
			_argumentPart1 = [_argumentPart1 stringByTrimmingCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @"\"'"]];
			[finalArguments addObject: _argumentPart1];
			
			NSString *_argumentPart2 = [_argumentComponent substringFromIndex: firstSpaceLocation + 1];
			NSString *bundlePath = [[NSBundle mainBundle] pathForResource: @"ffpresets" ofType: @""];
			if (bundlePath) {
				_argumentPart2 = [_argumentPart2 stringByReplacingOccurrencesOfString:@"$PRESETSDIR" withString: bundlePath];
			}
			_argumentPart2 = [_argumentPart2 stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
			_argumentPart2 = [_argumentPart2 stringByTrimmingCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @"\"'"]];
			[finalArguments addObject: _argumentPart2];
			
		} else {
			// just add this whole ffmpeg argument, cause it has no variable
			if (![_argumentComponent hasPrefix: @"-"]) _argumentComponent = [NSString stringWithFormat: @"-%@", _argumentComponent]; // eventually add the missing prefix again, caused by the split
			_argumentComponent = [_argumentComponent stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
			_argumentComponent = [_argumentComponent stringByTrimmingCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @"\"'"]];
			[finalArguments addObject: _argumentComponent];
		}
		
	}	
	
	return finalArguments;
}



// LogWindow Functions

- (void) doLog: (NSString *) aLogMessage {
	[self doLog: aLogMessage withNewline: YES];
}

- (void) doLogWithoutNewline: (NSString *) aLogMessage {
	[self doLog: aLogMessage withNewline: NO];
}

- (void) doLog: (NSString *) aLogMessage withNewline: (BOOL) withNewLine {
/*
	float scrollPos;

	if ([statusText string].length == 0) scrollPos = 1.0;
	else scrollPos = [[statusTextScrollview verticalScroller] floatValue];    // Get the current scrollbar position
*/
	if(aLogMessage != nil) {
		NSString *newLine = withNewLine ? @"\n" : @"";
		[[[statusText textStorage] mutableString ] appendFormat: @"%@%@", aLogMessage, newLine];        
	}
	
	// Delete the old lines of text to keep the text a set number of lines
	if([[[statusText textStorage] paragraphs] count] > 200) {
		[[statusText textStorage] deleteCharactersInRange:NSMakeRange (0, [[[[statusText textStorage] paragraphs] objectAtIndex:0] length])];
	}
	
	// if the scrollbar *was all the way at the bottom before the new text was appended,
	// then scroll down to the bottom
//	if( scrollPos == 1.0 ) {
		NSRange range = NSMakeRange ([[statusText string] length], 0);
		
		[statusText scrollRangeToVisible: range];        //This method is O (N) for the number of lines!
//	}
}


// Settings Window Functions

- (IBAction) openSettingsWindow: (id) sender {
	[(NSMutableDictionary *)[myLinker content] setObject: [settingsTabs tabViewItemAtIndex: 0].label forKey: @"currentPrefTitle"];
	[settingsTabs selectTabViewItemAtIndex: 0];
	[preferencesWindow makeKeyAndOrderFront: sender];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
	if (tabView == settingsTabs) {
		[(NSMutableDictionary *)[myLinker content] setObject: [tabViewItem label] forKey: @"currentPrefTitle"];
	}
}


- (void) settings_selectGeneral: (id) sender {
	[settingsTabs selectTabViewItemWithIdentifier: @"general"];
}
- (void) settings_selectFFMPEGSettings: (id) sender {
	[settingsTabs selectTabViewItemWithIdentifier: @"ffmpeg"];
}
- (void) settings_selectMonitorSettings: (id) sender {
	[settingsTabs selectTabViewItemWithIdentifier: @"monitor"];
}
- (void) settings_selectTVShowDetection: (id) sender {
	[settingsTabs selectTabViewItemWithIdentifier: @"tvshowdetection"];
}
- (void) settings_selectUpdate: (id) sender {
	[settingsTabs selectTabViewItemWithIdentifier: @"update"];
}

- (void) changeMoveMonitoredSuccessFolder: (id) sender {	
	NSOpenPanel *selectFilesDialog = [NSOpenPanel openPanel];
	[selectFilesDialog setCanChooseFiles: NO];
	[selectFilesDialog setCanChooseDirectories: YES];
	[selectFilesDialog setAllowsMultipleSelection: NO];
	[selectFilesDialog beginSheetForDirectory: nil file: nil types: nil modalForWindow: preferencesWindow modalDelegate: self didEndSelector: @selector(changeMoveMonitoredSuccessFolderDialogDidEnd:returnCode:contextInfo:) contextInfo: nil];
}
- (void) changeMoveMonitoredSuccessFolderDialogDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode contextInfo:(void *) popupButton {
	if (returnCode == NSOKButton) {
		if ([panel filenames].count) {
			NSString *monitorFolder = [[panel filenames] objectAtIndex: 0];
			[[NSUserDefaults standardUserDefaults] setObject: monitorFolder forKey: @"moveMonitoredSuccessFolder"];
			[moveSourcePopupButton removeItemAtIndex: 0];
			[moveSourcePopupButton insertItemWithTitle: monitorFolder atIndex:0];
			[[moveSourcePopupButton itemAtIndex: 0] setTag: 1];
			[[moveSourcePopupButton itemAtIndex: 0] setHidden: NO];
			[[moveSourcePopupButton itemAtIndex: 1] setHidden: NO];
			[moveSourcePopupButton selectItemWithTag: 1];
		}
	} else {
		if ([[[NSUserDefaults standardUserDefaults] objectForKey:@"moveMonitoredSuccessFolder"] hasPrefix: @"/"]) [moveSourcePopupButton selectItemWithTag: 1];
		else [moveSourcePopupButton selectItemWithTag: 2];
	}
}
- (void) changeMoveMonitoredSuccessFolderToDefault: (id) sender {	
	[[NSUserDefaults standardUserDefaults] setObject: @"Folder named 'imported' within the sources' folder" forKey: @"moveMonitoredSuccessFolder"];
	[[moveSourcePopupButton itemAtIndex: 0] setHidden: YES];
	[[moveSourcePopupButton itemAtIndex: 1] setHidden: YES];
	[moveSourcePopupButton selectItemWithTag: 2];
}

- (void) changeTempMonitoredFolder: (id) sender {
	NSOpenPanel *selectFilesDialog = [NSOpenPanel openPanel];
	[selectFilesDialog setCanChooseFiles: NO];
	[selectFilesDialog setCanChooseDirectories: YES];
	[selectFilesDialog setAllowsMultipleSelection: NO];
	[selectFilesDialog beginSheetForDirectory: nil file: nil types: nil modalForWindow: preferencesWindow modalDelegate: self didEndSelector: @selector(changeTempMonitoredFolderDialogDidEnd:returnCode:contextInfo:) contextInfo: nil];
}
- (void) changeTempMonitoredFolderDialogDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode contextInfo:(void *) popupButton {
	if (returnCode == NSOKButton) {
		if ([panel filenames].count) {
			NSString *tempMonitoredFolder = [[panel filenames] objectAtIndex: 0];
			[[NSUserDefaults standardUserDefaults] setObject: tempMonitoredFolder forKey: @"tempMonitoredFolder"];
			[tempMonitoredFolderPopupButton removeItemAtIndex: 0];
			[tempMonitoredFolderPopupButton insertItemWithTitle: tempMonitoredFolder atIndex:0];
			[[tempMonitoredFolderPopupButton itemAtIndex: 0] setTag: 1];
			[[tempMonitoredFolderPopupButton itemAtIndex: 0] setHidden: NO];
			[[tempMonitoredFolderPopupButton itemAtIndex: 1] setHidden: NO];
			[tempMonitoredFolderPopupButton selectItemAtIndex: 0];
		}
	} else {
		if ([[[NSUserDefaults standardUserDefaults] objectForKey:@"tempMonitoredFolder"] hasPrefix: @"/"]) [tempMonitoredFolderPopupButton selectItemWithTag: 1];
		else [tempMonitoredFolderPopupButton selectItemWithTag: 2];
	}
}
- (void) changeTempMonitoredFolderToDefault: (id) sender {
	[[NSUserDefaults standardUserDefaults] setObject: @"Folder named 'queued' within the monitored folder" forKey: @"tempMonitoredFolder"];
	[[tempMonitoredFolderPopupButton itemAtIndex: 0] setHidden: YES];
	[[tempMonitoredFolderPopupButton itemAtIndex: 1] setHidden: YES];
	[tempMonitoredFolderPopupButton selectItemWithTag: 2];	
}

- (void) changeImportDestination: (id) sender {
	NSOpenPanel *selectFilesDialog = [NSOpenPanel openPanel];
	[selectFilesDialog setCanChooseFiles: NO];
	[selectFilesDialog setCanChooseDirectories: YES];
	[selectFilesDialog setAllowsMultipleSelection: NO];
	[selectFilesDialog beginSheetForDirectory: nil file: nil types: nil modalForWindow: preferencesWindow modalDelegate: self didEndSelector: @selector(changeImportDestinationDialogDidEnd:returnCode:contextInfo:) contextInfo: nil];
}
- (void) changeImportDestinationDialogDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode contextInfo:(void *) popupButton {
	if (returnCode == NSOKButton) {
		if ([panel filenames].count) {
			NSString *tempMonitoredFolder = [[panel filenames] objectAtIndex: 0];
			[[NSUserDefaults standardUserDefaults] setObject: tempMonitoredFolder forKey: @"importDestination"];
			[importDestinationPopupButton removeItemAtIndex: 0];
			[importDestinationPopupButton insertItemWithTitle: tempMonitoredFolder atIndex:0];
			[[importDestinationPopupButton itemAtIndex: 0] setTag: 1];
			[[importDestinationPopupButton itemAtIndex: 0] setHidden: NO];
			[[importDestinationPopupButton itemAtIndex: 1] setHidden: NO];
			[importDestinationPopupButton selectItemWithTag: 1];
		}
	} else {
		if ([[[NSUserDefaults standardUserDefaults] objectForKey:@"importDestination"] hasPrefix: @"/"]) [importDestinationPopupButton selectItemWithTag: 1];
		else [importDestinationPopupButton selectItemWithTag: 2];
	}
}
- (void) changeImportDestinationToiTunes: (id) sender {
	[[NSUserDefaults standardUserDefaults] setObject: @"iTunes" forKey: @"importDestination"];
	[[importDestinationPopupButton itemAtIndex: 0] setHidden: YES];
	[[importDestinationPopupButton itemAtIndex: 1] setHidden: YES];
	[importDestinationPopupButton selectItemWithTag: 2];	
}


- (IBAction) showAboutDialog: (id) sender {
	[[NSApplication sharedApplication] orderFrontStandardAboutPanelWithOptions: [NSDictionary dictionaryWithObjectsAndKeys: @"", nil]];
}

- (IBAction) visitTVDetectionWiki: (id) sender {
	[[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: @"http://code.google.com/p/medianox/wiki/TVDetection"]];
}

@end
