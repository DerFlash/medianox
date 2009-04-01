//
//  isActiveTransformer.m
//  MediaNox
//
//  Created by Björn Teichmann on 21.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "isActiveTransformer.h"


@implementation isActiveTransformer

- (id) init {
	if (self = [super init]) {
		[NSValueTransformer setValueTransformer: self forName: @"isActiveTransformer"];
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
	if ([value isKindOfClass: [NSArray class]]) {
		for (NSNumber *_status in value) {
			if ([_status intValue] > 0) return @"YES";
		}
		return @"NO";
	}
	
 	if ([value intValue] > 0) return [NSNumber numberWithBool: YES];
	else return [NSNumber numberWithBool: NO];
}

@end
