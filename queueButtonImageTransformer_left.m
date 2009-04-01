//
//  queueButtonImageTransformer_left.m
//  MediaNox
//
//  Created by Björn Teichmann on 19.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "queueButtonImageTransformer_left.h"


@implementation queueButtonImageTransformer_left

- (id) init {
	if (self = [super init]) {
		[NSValueTransformer setValueTransformer: self forName: @"queueButtonImageTransformer_left"];
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
	if ([value boolValue]) return [NSImage imageNamed: @"label_HideQueueL.png"];
	else return [NSImage imageNamed: @"label_ShowQueueL.png"];
}


@end
