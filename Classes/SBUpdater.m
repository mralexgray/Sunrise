/*

SBUpdater.m
 
Authoring by Atsushi Jike

Copyright 2010 Atsushi Jike. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, 
are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer 
in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, 
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import "SBUpdater.h"
#import "SBAdditions.h"

@implementation SBUpdater

@synthesize raiseResult;
@synthesize checkSkipVersion;

static SBUpdater *_sharedUpdater;

+ (id)sharedUpdater
{
	if (!_sharedUpdater)
	{
		_sharedUpdater = [[SBUpdater alloc] init];
	}
	return _sharedUpdater;
}

- (id)init
{
	if (self = [super init])
	{
		raiseResult = NO;
		checkSkipVersion = YES;
	}
	return self;
}

- (void)dealloc
{
	[super dealloc];
}

- (void)check
{
	[NSThread detachNewThreadSelector:@selector(checking) toTarget:self withObject:nil];
}

- (void)checking
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSComparisonResult result = NSOrderedSame;
	NSString *appVersionString = [[NSBundle mainBundle] infoDictionary][@"CFBundleVersion"];
	NSURL *url = [NSURL URLWithString:SBVersionFileURL];
	NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:kSBTimeoutInterval];
	NSURLResponse *responce = nil;
	NSError *error = nil;
	NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&responce error:&error];
	NSThread *currentThread = [NSThread currentThread];
	NSMutableDictionary *threadDictionary = [currentThread threadDictionary];
	
	threadDictionary[kSBUpdaterResult] = @(result);
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(threadWillExit:) name:NSThreadWillExitNotification object:currentThread];
	
	if (data && appVersionString)
	{
		// Success for networking
		// Parse data
		NSString *string = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		if ([string length] > 0)
		{
			NSRange range0;
			range0 = [string rangeOfString:@"version=\""];
			if (range0.location != NSNotFound)
			{
				NSRange range1;
				range1 = [string rangeOfString:@"\";" options:0 range:NSMakeRange(NSMaxRange(range0), [string length] - NSMaxRange(range0))];
				if (range1.location != NSNotFound)
				{
					NSString *versionString = nil;
					range0 = NSMakeRange(NSMaxRange(range0), range1.location - NSMaxRange(range0));
					versionString = [string substringWithRange:range0];
					if ([versionString length] > 0)
					{
						result = [appVersionString compareAsVersionString:versionString];
						threadDictionary[kSBUpdaterResult] = @(result);
						if (result == NSOrderedAscending)
						{
							// Should update
							threadDictionary[kSBUpdaterVersionString] = versionString;
						}
						else if (result == NSOrderedSame)
						{
							// Not need updating
							threadDictionary[kSBUpdaterVersionString] = versionString;
						}
					}
				}
			}
		}
	}
	else {
		// Error
		threadDictionary[kSBUpdaterErrorDescription] = NSLocalizedString(@"Could not check for updates.", nil);
	}
	[pool release];
}

- (void)threadWillExit:(NSNotification*)aNotification
{
	NSThread *currentThread = [aNotification object];
	NSMutableDictionary *threadDictionary = [currentThread threadDictionary];
	NSString *errorDescription = threadDictionary[kSBUpdaterErrorDescription];
	NSDictionary *userInfo = [[threadDictionary copy] autorelease];
	if (!errorDescription)
	{
		NSComparisonResult result = [userInfo[kSBUpdaterResult] integerValue];
		if (result == NSOrderedAscending)
		{
			BOOL shouldSkip = NO;
			if (checkSkipVersion)
			{
				NSString *versionString = userInfo[kSBUpdaterVersionString];
				NSString *skipVersion = [[NSUserDefaults standardUserDefaults] objectForKey:kSBUpdaterSkipVersion];
				shouldSkip = [versionString isEqualToString:skipVersion];
			}
			if (!shouldSkip)
			{
				[self performSelectorOnMainThread:@selector(postShouldUpdateNotification:) withObject:userInfo waitUntilDone:NO];
			}
		}
		else if (result == NSOrderedSame)
		{
			if (raiseResult)
			{
				[self performSelectorOnMainThread:@selector(postNotNeedUpdateNotification:) withObject:userInfo waitUntilDone:NO];
			}
		}
		else if (result == NSOrderedDescending)
		{
			if (raiseResult)
			{
				// Error
				threadDictionary[kSBUpdaterErrorDescription] = NSLocalizedString(@"Invalid version number.", nil);
				userInfo = [[threadDictionary copy] autorelease];
				[self performSelectorOnMainThread:@selector(postDidFailCheckingNotification:) withObject:userInfo waitUntilDone:NO];
			}
		}
	}
	else {
		if (raiseResult)
		{
			[self performSelectorOnMainThread:@selector(postDidFailCheckingNotification:) withObject:userInfo waitUntilDone:NO];
		}
	}
}

- (void)postShouldUpdateNotification:(NSDictionary *)userInfo
{
	[[NSNotificationCenter defaultCenter] postNotificationName:SBUpdaterShouldUpdateNotification object:self userInfo:userInfo];
}

- (void)postNotNeedUpdateNotification:(NSDictionary *)userInfo
{
	[[NSNotificationCenter defaultCenter] postNotificationName:SBUpdaterNotNeedUpdateNotification object:self userInfo:userInfo];
}

- (void)postDidFailCheckingNotification:(NSDictionary *)userInfo
{
	[[NSNotificationCenter defaultCenter] postNotificationName:SBUpdaterDidFailCheckingNotification object:self userInfo:userInfo];
}

@end
