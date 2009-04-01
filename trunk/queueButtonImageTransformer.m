//
//  queueButtonImageTransformer.m
//
//  Created by Björn Teichmann on 09.01.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "queueButtonImageTransformer.h"


@implementation queueButtonImageTransformer

- (id) init {
	if (self = [super init]) {
		[NSValueTransformer setValueTransformer: self forName: @"queueButtonImageTransformer"];
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
	if ([value boolValue]) return [NSImage imageNamed: @"label_HideQueue.png"];
	else return [NSImage imageNamed: @"label_ShowQueue.png"];
}

@end
