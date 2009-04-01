//
//  statusFontTransformer.m
//  MediaNox
//
//  Created by Björn Teichmann on 20.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "statusFontTransformer.h"


@implementation statusFontTransformer

- (id) init {
	if (self = [super init]) {
		[NSValueTransformer setValueTransformer: self forName: @"statusFontTransformer"];
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
	if ([value intValue] > 0) return [NSColor textColor];
	else if ([value intValue] == -1) return [NSColor colorWithDeviceRed:0.235 green:0.47 blue:0.27 alpha: 1];
	else if ([value intValue] < -1) return [NSColor colorWithDeviceRed:0.55 green:0.17 blue:0.17 alpha: 1];
	else return [NSColor lightGrayColor];
}



@end
