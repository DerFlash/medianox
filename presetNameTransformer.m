//
//  presetNameTransformer.m
//  MediaNox
//
//  Created by Björn Teichmann on 21.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "presetNameTransformer.h"


@implementation presetNameTransformer

- (id) init {
	if (self = [super init]) {
		[NSValueTransformer setValueTransformer: self forName: @"presetNameTransformer"];
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
	NSLog(@"V:%@",value);
	return value;
}

@end
