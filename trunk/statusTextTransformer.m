//
//  statusTextTransformer.m
//  MediaNox
//
//  Created by Björn Teichmann on 20.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "statusTextTransformer.h"


@implementation statusTextTransformer

- (id) init {
	if (self = [super init]) {
		[NSValueTransformer setValueTransformer: self forName: @"statusTextTransformer"];
	}
	return self;
}

+ (Class)transformedValueClass {
	return [NSImage class];
}

+ (BOOL)allowsReverseTransformation {
	return NO;
}

- (id)transformedValue:(id)value {
	if ([value intValue] == 0) return @"Queued";
	else if ([value intValue] == 1) return @"Converting";
	else if ([value intValue] == 2) return @"Importing";
	else if ([value intValue] == -1) return @"Done";
	else if ([value intValue] < -1) return @"Failed";
	else return @"Unknown";
}

@end
