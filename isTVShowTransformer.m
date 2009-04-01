//
//  isTVShowTransformer.m
//  MediaNox
//
//  Created by Björn Teichmann on 22.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "isTVShowTransformer.h"


@implementation isTVShowTransformer
- (id) init {
	if (self = [super init]) {
		[NSValueTransformer setValueTransformer: self forName: @"isTVShowTransformer"];
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
	if ([value isEqualToString: @"TV Show"]) return @"NO";
	else return @"YES";
}

@end
