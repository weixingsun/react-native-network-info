//
//  RNNetworkInfo.h
//  RNNetworkInfo
//
//  Created by Corey Wilson on 7/12/15.
//  Copyright (c) 2015 eastcodes. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <RCTBridge.h>
#import "wol.h"
#import "SimplePing.h"


@interface RNNetworkInfo : NSObject<RCTBridgeModule, SimplePingDelegate>

@property (nonatomic, strong, readwrite, nullable) SimplePing* pinger;
@property (nonatomic, strong, readwrite, nullable) RCTResponseSenderBlock callback;
@property (nonatomic, strong, readwrite, nullable) NSTimer* sendTimer;

@end
