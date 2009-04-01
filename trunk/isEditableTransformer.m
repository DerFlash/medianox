//
//  isEditableTransformer.m
//  MediaNox
//
//  Created by Björn Teichmann on 23.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "isEditableTransformer.h"


@implementation isEditableTransformer
- (id) init {
	if (self = [super init]) {
		[NSValueTransformer setValueTransformer: self forName: @"isEditableTransformer"];
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
	if ([value intValue] == 0 || [value intValue] == 1) return @"YES";
	else return @"NO";
}

@end
