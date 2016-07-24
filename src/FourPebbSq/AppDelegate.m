//
//  AppDelegate.m
//  FourPebbSq
//
//  Created by James Billingham on 22/06/2013.
//  Copyright (c) 2013 GoPebblr. All rights reserved.
//

#import "AppDelegate.h"
#import <PebbleKit/PebbleKit.h>
#import <CoreLocation/CoreLocation.h>
#import "BZFoursquare.h"
#import "KBPebbleMessageQueue.h"

@interface AppDelegate () <PBPebbleCentralDelegate, BZFoursquareSessionDelegate, BZFoursquareRequestDelegate, CLLocationManagerDelegate>
{
	BZFoursquare* _foursquare;
  CLLocationManager* _locationManager;
	KBPebbleMessageQueue* _messageQueue;
}
@end

@implementation AppDelegate

- (BOOL) application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
	_locationManager = [[CLLocationManager alloc] init];
  _locationManager.distanceFilter = 50.0;
  _locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters;
  _locationManager.delegate = self;
  [_locationManager startUpdatingLocation];
	
	_messageQueue = [[KBPebbleMessageQueue alloc] init];
	
	_foursquare = [[BZFoursquare alloc] initWithClientID:@"55O3SYW5JUPYMLC1OWYBM4PH25OYMJGXLCUDEUIATRNLMDQ0" callbackURL:@"fourpebbsq://4sq"];
	_foursquare.version = @"20130622";
	_foursquare.sessionDelegate = self;
	
	NSString* accessToken = [NSUserDefaults.standardUserDefaults objectForKey:@"access_token"];
	
	if (accessToken != nil)
		_foursquare.accessToken = accessToken;
	
	if (!_foursquare.isSessionValid)
		[_foursquare startAuthorization];
	
	else
		[self foursquareDidAuthorize:_foursquare];
	
	return true;
}

- (BOOL) application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation
{
	if ([url.scheme isEqualToString:@"fourpebbsq"])
		return [_foursquare handleOpenURL:url];
	
	return false;
}

- (void) pebbleCentral:(PBPebbleCentral*)central watchDidConnect:(PBWatch*)watch isNew:(BOOL)isNew
{
	[self setupWatch:watch];
}

- (void) pebbleCentral:(PBPebbleCentral*)central watchDidDisconnect:(PBWatch*)watch
{
	[[[UIAlertView alloc] initWithTitle:@"Disconnected!" message:[watch name] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
	
	if (_messageQueue.watch == watch || [watch isEqual:_messageQueue.watch])
		[self setupWatch:nil];
}

- (void) foursquareDidAuthorize:(BZFoursquare*)foursquare
{
	[NSUserDefaults.standardUserDefaults setObject:foursquare.accessToken forKey:@"access_token"];
	[NSUserDefaults.standardUserDefaults synchronize];
	
	PBPebbleCentral.defaultCentral.delegate = self;
	
	[self setupWatch:PBPebbleCentral.defaultCentral.lastConnectedWatch];
}

- (void) foursquareDidNotAuthorize:(BZFoursquare*)foursquare error:(NSDictionary*)errorInfo
{
	[[[UIAlertView alloc] initWithTitle:@"Error" message:@"Foursquare authorization failed" delegate:nil cancelButtonTitle:@"Okay" otherButtonTitles:nil] show];
}

- (void) setupWatch:(PBWatch*)watch
{
	_messageQueue.watch = watch;
	
	[watch appMessagesGetIsSupported:^(PBWatch* watch, BOOL isAppMessagesSupported)
	{
		if (!isAppMessagesSupported)
		{
			[[[UIAlertView alloc] initWithTitle:@"Error" message:@"Pebble doesn't support AppMessages" delegate:nil cancelButtonTitle:@"Okay" otherButtonTitles:nil] show];
			return;
		}
		
		uint8_t bytes[] = { 0x4E, 0x1A, 0x5A, 0x91, 0x9E, 0xB0, 0x45, 0x2A, 0xB7, 0x52, 0xD4, 0x42, 0x64, 0xB1, 0x89, 0xB6 };
		NSData* uuid = [NSData dataWithBytes:bytes length:sizeof(bytes)];
		[watch appMessagesSetUUID:uuid];
		
		[watch appMessagesAddReceiveUpdateHandler:^BOOL(PBWatch* watch, NSDictionary* update)
		{
			NSString* action = update[@(0)];
			NSLog(@"%@", update);
			
			CLLocation* location = _locationManager.location;
			CLLocationCoordinate2D coords = location.coordinate;
			NSString* llString = [NSString stringWithFormat:@"%f,%f", coords.latitude, coords.longitude];
			NSString* altString = [NSString stringWithFormat:@"%f", location.altitude];
			NSString* llAccString = [NSString stringWithFormat:@"%f", location.horizontalAccuracy];
			NSString* altAccString = [NSString stringWithFormat:@"%f", location.verticalAccuracy];
			
			if ([action isEqualToString:@"get_locations"])
			{
				[[_foursquare requestWithPath:[NSString stringWithFormat:@"venues/search"] HTTPMethod:@"GET" parameters:[[NSDictionary alloc] initWithObjectsAndKeys:llString, @"ll", altString, @"alt", llAccString, @"llAcc", altAccString, @"altAcc", @(10), @"limit", nil] delegate:self] start];
			}
			else if ([action isEqualToString:@"checkin"])
			{
				NSString* venue = update[@(1)];
				[[_foursquare requestWithPath:@"checkins/add" HTTPMethod:@"POST" parameters:[NSDictionary dictionaryWithObjectsAndKeys:venue, @"venueId", @"I checked in on my Pebble smartwatch with 4pebbSq!", @"shout", llString, @"ll", altString, @"alt", llAccString, @"llAcc", altAccString, @"altAcc", nil] delegate:self] start];
			}
			
			return true;
		}];
	}];
}

- (void) requestDidFinishLoading:(BZFoursquareRequest*)request
{
	NSDictionary* response = request.response;
	NSArray* keys = response.allKeys;
	
	if ([keys containsObject:@"venues"])
	{
		NSMutableArray* venues = [response[@"venues"] mutableCopy];
		
		[venues sortUsingDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"location.distance" ascending:true]]];
		
		for (NSDictionary* venue in venues)
		{
			NSString* subtitle = [NSString stringWithFormat:@"%@m away", venue[@"location"][@"distance"]];
			
			NSDictionary* newVenue = [[NSDictionary alloc] initWithObjectsAndKeys:
				@"add_venue", @(0),
				venue[@"id"], @(1),
				venue[@"name"], @(2),
				subtitle, @(3),
				nil];
			
			[_messageQueue enqueue:newVenue];
		}
		
		[_messageQueue enqueue:[[NSDictionary alloc] initWithObjectsAndKeys:@"completed_venues", @(0), nil]];
	}
	else if ([keys containsObject:@"checkin"])
	{
		//[_messageQueue enqueue:[NSDictionary dictionaryWithObjectsAndKeys:@"done", @(0), nil]];
	}
}

@end
