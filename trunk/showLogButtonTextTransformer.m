//
//  showLogButtonTextTransformer.m
//  MediaNox
//
//  Created by Björn Teichmann on 21.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "showLogButtonTextTransformer.h"


@implementation showLogButtonTextTransformer

- (id) init {
	if (self = [super init]) {
		[NSValueTransformer setValueTransformer: self forName: @"showLogButtonTextTransformer"];
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
	if ([value boolValue]) return @"Hide Log\n";
	else return @"Show Log\n";
}

@end
