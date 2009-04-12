//
//  selectedMoveMonitoredFolderTransformer.m
//  MediaNox
//
//  Created by Björn Teichmann on 24.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "selectedMoveMonitoredFolderTransformer.h"


@implementation selectedMoveMonitoredFolderTransformer

- (id) init {
	if (self = [super init]) {
		[NSValueTransformer setValueTransformer: self forName: @"selectedMoveMonitoredFolderTransformer"];
	}
	return self;
}

+ (Class)transformedValueClass {
	return [NSImage class];
}

+ (BOOL)allowsReverseTransformation {
	return NO;
}

- (id)transformedValue: (id) value {
	if ([value hasPrefix: @"/"]) {
		return [NSNumber numberWithInt: 1];
	}
	return [NSNumber numberWithInt: 2];
}


@end
