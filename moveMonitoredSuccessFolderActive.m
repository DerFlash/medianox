//
//  moveMonitoredSuccessFolderActive.m
//  MediaNox
//
//  Created by Björn Teichmann on 25.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "moveMonitoredSuccessFolderActive.h"


@implementation moveMonitoredSuccessFolderActive

- (id) init {
	if (self = [super init]) {
		[NSValueTransformer setValueTransformer: self forName: @"moveMonitoredSuccessFolderActive"];
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
	if ([value intValue] == 2) {
		return @"YES";
	}
	return @"NO";
}

@end
