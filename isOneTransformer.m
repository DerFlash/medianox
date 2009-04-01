//
//  isOneTransformer.m
//  MediaNox
//
//  Created by Björn Teichmann on 20.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "isOneTransformer.h"


@implementation isOneTransformer

- (id) init {
	if (self = [super init]) {
		[NSValueTransformer setValueTransformer: self forName: @"isOneTransformer"];
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
	if ([value intValue] == 1) return [NSNumber numberWithBool: YES];
	else return [NSNumber numberWithBool: NO];
}


@end
