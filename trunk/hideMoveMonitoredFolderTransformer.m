//
//  hideMoveMonitoredFolderTransformer.m
//  MediaNox
//
//  Created by Björn Teichmann on 24.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "hideMoveMonitoredFolderTransformer.h"


@implementation hideMoveMonitoredFolderTransformer

- (id) init {
	if (self = [super init]) {
		[NSValueTransformer setValueTransformer: self forName: @"hideMoveMonitoredFolderTransformer"];
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
		return @"NO";
	}
	return @"YES";
}


@end
