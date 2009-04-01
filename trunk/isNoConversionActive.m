//
//  isNoConversionActive.m
//  MediaNox
//
//  Created by Björn Teichmann on 23.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "isNoConversionActive.h"


@implementation isNoConversionActive

- (id) init {
	if (self = [super init]) {
		[NSValueTransformer setValueTransformer: self forName: @"isNoConversionActive"];
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
	for (NSNumber *_status in value) {
		if ([_status intValue] == 1) return @"NO";
	}
	return @"YES";
}

@end
