//
//  canReQueueTransformer.m
//  MediaNox
//
//  Created by Björn Teichmann on 22.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "canReQueueTransformer.h"


@implementation canReQueueTransformer
- (id) init {
	if (self = [super init]) {
		[NSValueTransformer setValueTransformer: self forName: @"canReQueueTransformer"];
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
	if ([value intValue] < 0) return @"YES";
	else return @"NO";
}
@end
