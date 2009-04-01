//
//  mediaTypeImageTransformer.m
//  MediaNox
//
//  Created by Björn Teichmann on 19.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "mediaTypeImageTransformer.h"


@implementation mediaTypeImageTransformer

- (id) init {
	if (self = [super init]) {
		[NSValueTransformer setValueTransformer: self forName: @"mediaTypeImageTransformer"];
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
	if ([value isEqualToString: @"Movie"]) return [NSImage imageNamed: @"type_movie.png"];
	else if ([value isEqualToString: @"TV Show"]) return [NSImage imageNamed: @"type_tvshow.png"];
	else return [NSImage imageNamed: @"type_unknown.png"];
}

@end
