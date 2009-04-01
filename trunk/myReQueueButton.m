//
//  myReQueueButton.m
//  MediaNox
//
//  Created by Björn Teichmann on 22.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "myReQueueButton.h"


@implementation myReQueueButton


- (id)initWithCoder:(NSCoder *) aDecoder {
    self = [super initWithCoder: aDecoder];
    if (self) {

    }
    return self;
}

- (void) setTarget: (id) _target {
	NSLog(@"setTarget:%@", [_target className]);
}

- (void) setAction: (SEL) _action {
	NSLog(@"setAction:%@", NSStringFromSelector(_action));
}

- (void) performClick: (id) sender {
	NSLog(@"PerformC");
}


@end
