//
//  DropView.m
//  MediaNox
//
//  Created by Björn Teichmann on 20.03.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "DropView.h"


@implementation DropView

- (id)initWithCoder:(NSCoder *) aCoder {
    self = [super initWithCoder: aCoder];
    if (self) {
		[self registerForDraggedTypes:[NSArray arrayWithObjects: NSFilenamesPboardType, nil]];
    }
    return self;
}


- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    if ((NSDragOperationGeneric & [sender draggingSourceOperationMask]) == NSDragOperationGeneric) {
        return NSDragOperationCopy;
    } else {
        return NSDragOperationNone;
    }
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender {
    if ((NSDragOperationGeneric & [sender draggingSourceOperationMask]) == NSDragOperationGeneric) {
        return NSDragOperationCopy;
    } else {
        return NSDragOperationNone;
    }
}



- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender {
    return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    NSPasteboard* pboard = [sender draggingPasteboard];
	
    if ( [[pboard types] containsObject:NSFilenamesPboardType] ) {
        NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
		if ([delegate respondsToSelector: @selector(queueTheseFiles:)]) [delegate performSelector: @selector(queueTheseFiles:) withObject: files];
	}
	return YES;
}



- (void)dealloc {
    [self unregisterDraggedTypes];
    [super dealloc];
}

@end
