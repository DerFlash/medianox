//
//  myTableButton.m
//  MediaNox
//
//  Created by Björn Teichmann on 22.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "myTableButton.h"


@implementation myTableButton

- (id)initWithCoder:(NSCoder *) aDecoder {
    self = [super initWithCoder: aDecoder];
    if (self) {
		
    }
    return self;
}


- (BOOL)showsBorderOnlyWhileMouseInside {
	return YES;
}

- (void)mouseEntered:(NSEvent *)event {
	NSLog(@"in");
}

- (void)mouseExited:(NSEvent *)event {
	NSLog(@"out");
}





- (void) dealloc {
	
	[super dealloc];
}

@end
